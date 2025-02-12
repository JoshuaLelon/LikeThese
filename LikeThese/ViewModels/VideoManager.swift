import Foundation
import AVFoundation
import Network
import FirebaseStorage
import FirebaseFirestore
import FirebaseFunctions

// Video errors
enum VideoError: Error {
    case invalidResponse
    case videoNotFound
    case networkError
}

enum VideoPlayerState: Equatable {
    case idle
    case loading(index: Int)
    case playing(index: Int)
    case paused(index: Int)
    case error(index: Int, error: Error)
    
    var currentIndex: Int? {
        switch self {
        case .idle: return nil
        case .loading(let index): return index
        case .playing(let index): return index
        case .paused(let index): return index
        case .error(let index, _): return index
        }
    }
    
    static func == (lhs: VideoPlayerState, rhs: VideoPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading(let index1), .loading(let index2)):
            return index1 == index2
        case (.playing(let index1), .playing(let index2)):
            return index1 == index2
        case (.paused(let index1), .paused(let index2)):
            return index1 == index2
        case (.error(let index1, _), .error(let index2, _)):
            return index1 == index2
        default:
            return false
        }
    }
}

private struct KeepRange {
    let start: Int
    let end: Int
    
    func contains(_ index: Int) -> Bool {
        return index >= start && index <= end
    }
}

enum CleanupContext {
    case navigation(from: Int, to: Int)
    case dismissal
    case error
}

enum PreloadState {
    case notStarted
    case loading(progress: Float)
    case verifying
    case ready
    case failed(Error)
    case timedOut
}

enum PreloadError: Error {
    case timeout
    case verificationFailed(String)
    case retryFailed
    case bufferingIncomplete
    case playerNotFound
}

enum TransitionState: Equatable {
    case none
    case gesture(from: Int, to: Int)
    case autoAdvance(from: Int, to: Int)
    case error
    
    var isActive: Bool {
        switch self {
        case .none:
            return false
        default:
            return true
        }
    }
    
    var indices: (from: Int, to: Int)? {
        switch self {
        case .gesture(let from, let to), .autoAdvance(let from, let to):
            return (from, to)
        case .none, .error:
            return nil
        }
    }
}

@MainActor
class VideoManager: NSObject, ObservableObject {
    // Singleton instance
    static let shared = VideoManager()
    
    // Firebase instances
    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let storage = Storage.storage()
    
    // Video data
    @Published private(set) var videos: [LikeTheseVideo] = []
    @Published private(set) var sortedCandidates: [(videoId: String, distance: Double)] = []
    @Published private(set) var nextVideoIndex: Int = 0
    
    // State tracking
    @Published private(set) var currentState: VideoPlayerState = .idle
    @Published private(set) var activeVideoIndex: Int?
    @Published private(set) var isTransitioning = false
    
    // Add transition state management
    @Published private(set) var transitionState: TransitionState = .none {
        didSet {
            isTransitioning = transitionState.isActive
        }
    }
    private var transitionQueue: [(TransitionState, () -> Void)] = []
    private var isProcessingTransition = false
    
    // Existing properties
    private var players: [Int: AVPlayer] = [:]
    private var preloadedPlayers: [Int: AVPlayer] = [:]
    private var timeObservers: [Int: (observer: Any, player: AVPlayer)] = [:]
    private var endTimeObservers: [Int: (observer: Any, player: AVPlayer)] = [:]
    private var playerItems: [Int: AVPlayerItem] = [:]
    private var completedVideos: Set<Int> = []
    private let videoCacheService = VideoCacheService.shared
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private var retryQueue: [(index: Int, url: URL)] = []
    private var playerUrls: [Int: URL] = [:]
    
    // Transition tracking
    private var transitionTask: Task<Void, Never>?
    private var preloadTasks: [Int: Task<Void, Error>] = [:]
    
    // Published states
    @Published private(set) var bufferingStates: [Int: Bool] = [:]
    @Published private(set) var bufferingProgress: [Int: Float] = [:]
    @Published private(set) var playerStates: [Int: String] = [:]
    @Published private(set) var networkState: String = "unknown"
    @Published private(set) var preloadStates: [Int: PreloadState] = [:]
    
    // Configuration
    private let preferredBufferDuration: TimeInterval = 30.0
    private let verificationTimeout: TimeInterval = 15.0
    private let minimumBufferDuration: TimeInterval = 5.0
    private let preloadWindowSize = 12
    private let preloadTriggerThreshold = 6
    
    var onVideoComplete: ((Int) -> Void)?
    
    private var isTransitioningToPlayback = false
    
    private var keepRange: KeepRange?
    private var pendingCleanup = Set<Int>()
    
    // Add state preservation
    private var preservedPlayers: [Int: AVPlayer] = [:]
    private var preservedStates: [Int: String] = [:]
    private var preservedItems: [Int: AVPlayerItem] = [:]
    
    private enum ObserverKey: Hashable {
        case buffer(index: Int)
        case status(index: Int)
    }
    
    // Update observers dictionary type
    private var observers: [ObserverKey: NSKeyValueObservation] = [:]
    
    // Private initializer for singleton
    private override init() {
        super.init()
        setupNetworkMonitoring()
        print("📱 VideoManager singleton initialized")
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            Task { @MainActor in
                self.isNetworkAvailable = path.status == .satisfied
                self.networkState = path.status == .satisfied ? "connected" : "disconnected"
                
                if path.status == .satisfied {
                    print("🌐 NETWORK: Connection restored")
                    await self.retryFailedLoads()
                } else {
                    print("🌐 NETWORK: Connection lost")
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func retryFailedLoads() async {
        print("🔄 NETWORK: Retrying \(self.retryQueue.count) failed loads")
        let itemsToRetry = self.retryQueue
        self.retryQueue.removeAll()
        
        for item in itemsToRetry {
            do {
                print("🔄 RETRY: Attempting to load video for index \(item.index)")
                try await preloadVideo(url: item.url, forIndex: item.index)
            } catch {
                print("❌ RETRY ERROR: Failed to reload video \(item.index): \(error.localizedDescription)")
                // Add back to queue if still failing
                self.retryQueue.append(item)
            }
        }
    }
    
    func player(for index: Int) -> AVPlayer? {
        return players[index]
    }
    
    func preloadVideo(url: URL, forIndex index: Int) async throws {
        print("🔄 PRELOAD: Starting preload for index \(index) with URL: \(url)")
        
        // Cancel any existing preload task for this index
        preloadTasks[index]?.cancel()
        preloadTasks[index] = nil
        
        // Update initial state
        await MainActor.run {
            self.preloadStates[index] = .loading(progress: 0.0)
            if case .idle = self.currentState {
                self.currentState = .loading(index: index)
            }
        }
        
        do {
            try await retryWithBackoff(maxAttempts: 3) {
                // Create player item with timeout
                let playerItem = try await self.withTimeout(seconds: 30) {
                    try await self.videoCacheService.preloadVideo(url: url)
                }
                
                // Verify player item is valid
                guard try await playerItem.asset.load(.isPlayable) else {
                    print("❌ PRELOAD ERROR: Asset is not playable for index \(index)")
                    throw PreloadError.verificationFailed("Asset is not playable")
                }
                
                // Create and configure player
                await MainActor.run {
                    let player = AVPlayer(playerItem: playerItem)
                    player.automaticallyWaitsToMinimizeStalling = true
                    
                    // Store player
                    self.cleanupVideo(for: index)
                    self.players[index] = player
                    self.playerItems[index] = playerItem
                    self.playerUrls[index] = url
                    
                    // Setup observers
                    self.setupPlayerObservers(for: player, at: index)
                    self.setupEndTimeObserver(for: player, at: index)
                    
                    // Update states
                    self.preloadStates[index] = .ready
                    if self.activeVideoIndex == index {
                        self.currentState = .paused(index: index)
                    }
                    
                    print("✅ PRELOAD: Successfully preloaded video at index \(index)")
                }
            }
        } catch {
            print("❌ PRELOAD ERROR: Failed to preload video \(index) after retries: \(error.localizedDescription)")
            
            // Add to retry queue if it's a network error
            if (error as NSError).domain == NSURLErrorDomain {
                self.retryQueue.append((index: index, url: url))
                print("🔄 PRELOAD: Added to retry queue - index: \(index)")
            }
            
            await MainActor.run {
                self.preloadStates[index] = .failed(error)
                if self.activeVideoIndex == index {
                    self.currentState = .error(index: index, error: error)
                }
            }
            throw error
        }
    }
    
    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual operation
            group.addTask {
                return try await operation()
            }
            
            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PreloadError.timeout
            }
            
            // Wait for the first task to complete
            guard let result = try await group.next() else {
                throw PreloadError.timeout
            }
            
            // Cancel any remaining tasks
            group.cancelAll()
            
            return result
        }
    }
    
    private func retryWithBackoff(maxAttempts: Int = 3, operation: @escaping () async throws -> Void) async throws {
        var attempt = 0
        var delay = 1.0 // Start with 1 second delay
        
        while attempt < maxAttempts {
            do {
                try await operation()
                return
            } catch {
                attempt += 1
                if attempt == maxAttempts {
                    throw error
                }
                
                print("🔄 RETRY: Attempt \(attempt) failed, retrying in \(delay) seconds")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2 // Exponential backoff
            }
        }
    }
    
    private func verifyPlayerItem(_ playerItem: AVPlayerItem) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var observer: NSKeyValueObservation?
            var hasCompleted = false
            
            observer = playerItem.observe(\.status) { item, _ in
                guard !hasCompleted else { return }
                
                switch item.status {
                case .readyToPlay:
                    hasCompleted = true
                    observer?.invalidate()
                    continuation.resume()
                    
                case .failed:
                    hasCompleted = true
                    observer?.invalidate()
                    let error = item.error ?? NSError(domain: "com.Gauntlet.LikeThese", 
                                                    code: -1, 
                                                    userInfo: [NSLocalizedDescriptionKey: "Player item failed to load"])
                    continuation.resume(throwing: PreloadError.verificationFailed(error.localizedDescription))
                    
                default:
                    break
                }
            }
            
            // Set timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(verificationTimeout * 1_000_000_000))
                if !hasCompleted {
                    hasCompleted = true
                    observer?.invalidate()
                    continuation.resume(throwing: PreloadError.timeout)
                }
            }
        }
    }
    
    private func setupPlayerObservers(for player: AVPlayer, at index: Int) {
        // Setup time observer
        let timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.handleTimeUpdate(time: time, for: player, at: index)
        }
        timeObservers[index] = (observer: timeObserver, player: player)
        
        // Setup buffering observer
        let bufferingObserver = player.currentItem?.observe(\.isPlaybackLikelyToKeepUp) { [weak self] currentItem, _ in
            guard let self = self else { return }
            Task { @MainActor in
                let isBuffering = !(currentItem.isPlaybackLikelyToKeepUp)
                if currentItem.status == .failed {
                    print("❌ PLAYBACK ERROR: Video \(index) failed to load: \(String(describing: currentItem.error))")
                    await self.retryLoadingIfNeeded(for: index)
                } else {
                    print("🎮 BUFFER STATE: Video \(index) buffering: \(isBuffering)")
                }
            }
        }
        observers[.buffer(index: index)] = bufferingObserver
        
        // Setup status observer
        let statusObserver = player.currentItem?.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    print("✅ PLAYER: Video \(index) ready to play")
                    self.preloadStates[index] = .ready
                case .failed:
                    print("❌ PLAYER ERROR: Video \(index) failed: \(String(describing: item.error))")
                    self.preloadStates[index] = .failed(item.error ?? NSError())
                case .unknown:
                    print("⏳ PLAYER: Video \(index) in unknown state")
                @unknown default:
                    break
                }
            }
        }
        
        // Store status observer
        if let statusObserver = statusObserver {
            observers[.status(index: index)] = statusObserver
        }
        
        print("👀 OBSERVERS: Set up observers for video at index \(index)")
    }
    
    private func removePlayerObservers(for player: AVPlayer, at index: Int) {
        // Remove time observer
        if let (observer, observerPlayer) = timeObservers[index] {
            observerPlayer.removeTimeObserver(observer)
            timeObservers[index] = nil
        }
        
        // Remove buffering observer
        observers[.buffer(index: index)]?.invalidate()
        observers[.buffer(index: index)] = nil
        
        // Remove status observer
        observers[.status(index: index)]?.invalidate()
        observers[.status(index: index)] = nil
        
        print("👀 OBSERVERS: Removed observers for video at index \(index)")
    }
    
    private func setupEndTimeObserver(for player: AVPlayer, at index: Int) {
        // Reset completion state when setting up new observer
        Task { @MainActor in
            completedVideos.remove(index)
        }
        
        // Add observer for video end and state changes
        let observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self,
                  let currentItem = player.currentItem,
                  !CMTimeGetSeconds(time).isNaN,
                  !CMTimeGetSeconds(currentItem.duration).isNaN else { return }
            
            // Handle state changes
            Task { @MainActor in
                let oldState = self.playerStates[index]
                let stateStr: String
                switch player.timeControlStatus {
                case .playing:
                    stateStr = "playing"
                    if oldState != "playing" {
                        print("✅ PLAYBACK SUCCESS: Video \(index) successfully started playing")
                        // Reset completion state when video starts playing from beginning
                        let currentTime = CMTimeGetSeconds(time)
                        if currentTime < 1.0 {
                            self.completedVideos.remove(index)
                            print("🔄 COMPLETION STATE: Reset completion state for video \(index) - starting from beginning")
                        }
                    }
                case .paused:
                    stateStr = "paused"
                    if oldState != "paused" {
                        print("✅ PLAYBACK SUCCESS: Video \(index) successfully paused")
                    }
                case .waitingToPlayAtSpecifiedRate:
                    stateStr = "buffering"
                    if oldState != "buffering" {
                        print("⏳ PLAYBACK WAIT: Video \(index) waiting to play (possibly buffering)")
                    }
                @unknown default:
                    stateStr = "unknown"
                    if oldState != "unknown" {
                        print("⚠️ PLAYBACK WARNING: Video \(index) in unknown state")
                    }
                }
                
                if oldState != stateStr {
                    print("🎮 PLAYER STATE: Video \(index) state changed: \(oldState ?? "none") -> \(stateStr)")
                    self.playerStates[index] = stateStr
                }
                
                // Handle video completion
                let currentTime = CMTimeGetSeconds(time)
                let duration = CMTimeGetSeconds(currentItem.duration)
                let timeRemaining = duration - currentTime
                let isNearEnd = timeRemaining <= 0.15 // Slightly more lenient end detection
                
                // Calculate what percentage of the video has been played
                let percentagePlayed = (currentTime / duration) * 100
                
                // Only trigger completion if:
                // 1. Video is near the end
                // 2. Video is currently playing
                // 3. We haven't already marked this video as completed
                // 4. We've watched at least 50% of the video
                // 5. Player is not seeking/scrubbing
                // 6. No active transition is in progress
                if isNearEnd && 
                   player.timeControlStatus == .playing && 
                   !self.completedVideos.contains(index) && 
                   percentagePlayed >= 50 &&
                   currentItem.status == .readyToPlay &&
                   !self.transitionState.isActive {
                    
                    // Double check we're really at the end by comparing with duration
                    let actualTimeRemaining = duration - currentTime
                    guard actualTimeRemaining <= 0.15 else {
                        print("⚠️ COMPLETION CHECK: False end detection for video \(index) - actual time remaining: \(String(format: "%.2f", actualTimeRemaining))s")
                        return
                    }
                    
                    // Mark video as completed
                    self.completedVideos.insert(index)
                    
                    // Explicit video completion logging
                    print("🎬 VIDEO COMPLETED: Video at index \(index) has finished playing completely")
                    print("📊 VIDEO COMPLETION STATS: Video \(index) reached its end after \(String(format: "%.1f", duration))s total playback time")
                    print("📊 VIDEO COMPLETION STATS: Watched \(String(format: "%.1f", percentagePlayed))% of video")
                    print("🔄 VIDEO COMPLETION ACTION: Video \(index) finished naturally while playing - initiating auto-advance sequence")
                    
                    // Begin auto-advance transition
                    self.beginTransition(.autoAdvance(from: index, to: index + 1)) {
                        // Pause the current video to prevent looping
                        player.pause()
                        
                        // Trigger completion callback after a short delay to ensure pause takes effect
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            Task { @MainActor in
                                self.onVideoComplete?(index)
                            }
                        }
                    }
                }
            }
        }
        endTimeObservers[index] = (observer: observer, player: player)
        print("👀 COMPLETION OBSERVER: Successfully set up video completion monitoring for index \(index)")
    }
    
    func prepareForPlayback(at index: Int) {
        print("🎮 TRANSITION: Preparing for video playback at index \(index)")
        
        // First try to restore preserved state
        if preservedPlayers[index] != nil {
            restorePlayerState(for: index)
            return
        }
        
        // If no preserved state, create new player
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        players[index] = player
        setupPlayerObservers(for: player, at: index)
        print("🎮 PLAYER: Created new player for index \(index)")
    }
    
    func startPlaying(at index: Int) {
        guard let player = players[index] else {
            print("❌ PLAYBACK ERROR: No player found for index \(index)")
            currentState = .error(index: index, error: NSError(domain: "com.Gauntlet.LikeThese", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player not found"]))
            return
        }
        
        player.play()
        currentState = .playing(index: index)
        print("▶️ PLAYBACK: Started playing video \(index)")
    }
    
    func pausePlaying(at index: Int) {
        guard let player = players[index] else {
            print("❌ PLAYBACK ERROR: No player found for index \(index)")
            return
        }
        
        player.pause()
        currentState = .paused(index: index)
        print("⏸️ PLAYBACK: Paused video \(index)")
    }
    
    func togglePlayPauseAction(index: Int) {
        print("👆 TOGGLE: Requested for index \(index)")
        
        guard let player = players[index] else {
            print("❌ PLAYBACK ERROR: No player found for index \(index)")
            currentState = .error(index: index, error: NSError(domain: "com.Gauntlet.LikeThese", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player not found"]))
            return
        }
        
        switch player.timeControlStatus {
        case .playing:
            pausePlaying(at: index)
            
        case .paused:
            startPlaying(at: index)
            
        case .waitingToPlayAtSpecifiedRate:
            currentState = .loading(index: index)
            print("⏳ PLAYBACK: Video \(index) is buffering")
            
        @unknown default:
            print("❌ PLAYBACK ERROR: Unknown player state for index \(index)")
        }
    }
    
    func pauseAllExcept(index: Int) {
        print("🔄 SYSTEM: Pausing all players except index \(index)")
        players.forEach { key, player in
            if key != index {
                player.pause()
                print("🔄 SYSTEM: Paused player at index \(key)")
            } else if !completedVideos.contains(key) {
                // Only play if the video hasn't completed
                print("🔄 SYSTEM: Playing video at index \(key)")
                player.play()
            } else {
                print("⏸️ SYSTEM: Not playing completed video at index \(key)")
            }
        }
    }
    
    func cleanup(context: CleanupContext) {
        print("🧹 CLEANUP: Starting cleanup with context: \(String(describing: context))")
        
        switch context {
        case .navigation(let from, let to):
            // During navigation, preserve state of source and destination
            preservePlayerState(for: from)
            if let player = players[to] {
                preservePlayerState(for: to)
            }
            
            // Cleanup other resources outside the navigation range
            let keepRange = KeepRange(start: min(from, to) - 1, end: max(from, to) + 1)
            cleanupResourcesOutside(keepRange)
            
        case .dismissal:
            // On dismissal, preserve current state before cleanup
            if let current = activeVideoIndex {
                preservePlayerState(for: current)
            }
            cleanupAllResources()
            
        case .error:
            // On error, just clean everything
            cleanupAllResources()
        }
        
        // Reset transition state
        isTransitioning = false
        transitionTask?.cancel()
        transitionTask = nil
        
        print("✨ CLEANUP: Cleanup completed")
    }
    
    // Add public access to current player
    func currentPlayer(at index: Int) -> AVPlayer? {
        return players[index]
    }
    
    // Add seek to beginning helper
    func seekToBeginning(at index: Int) async {
        if let player = players[index] {
            print("⏪ PLAYBACK ACTION: Seeking video \(index) to beginning")
            // Reset completion state when seeking to beginning
            completedVideos.remove(index)
            await player.seek(to: CMTime.zero)
            player.play()
            print("▶️ PLAYBACK ACTION: Restarted video \(index) from beginning")
        }
    }
    
    private func cleanupObservers(for index: Int) {
        print("🧹 CLEANUP: Starting observer cleanup for index \(index)")
        
        // Remove time observer if it exists
        if let observerData = timeObservers[index] {
            observerData.player.removeTimeObserver(observerData.observer)
            print("🧹 CLEANUP: Removed time observer for index \(index)")
            timeObservers[index] = nil
        }
        
        // Remove KVO observer if it exists
        if let observer = observers[.buffer(index: index)] {
            observer.invalidate()
            observers[.buffer(index: index)] = nil
            print("🧹 CLEANUP: Removed KVO observer for index \(index)")
        }
        
        // Remove end time observer if it exists
        if let observerData = endTimeObservers[index] {
            observerData.player.removeTimeObserver(observerData.observer)
            print("🧹 CLEANUP: Removed end time observer for index \(index)")
            endTimeObservers[index] = nil
        }
        
        // Clear player item reference
        playerItems[index] = nil
        
        // Clear states
        bufferingStates[index] = nil
        bufferingProgress[index] = nil
        playerStates[index] = nil
        preloadStates[index] = nil
        
        print("✨ CLEANUP: Completed observer cleanup for index \(index)")
    }
    
    // Add public method to check distant players
    func getDistantPlayers(from currentIndex: Int) -> [Int] {
        // Only consider players more than 1 position away to keep adjacent videos ready
        return players.keys.filter { abs($0 - currentIndex) > 1 }
    }
    
    // Remove old cleanup methods that are now handled by centralized cleanup
    func cleanupVideo(for index: Int) {
        performCleanup(for: index)
    }

    func cleanupAllVideos() {
        cleanup(context: .dismissal)
    }

    private func performCleanup(for index: Int) {
        print("🧹 CLEANUP: Performing cleanup for index \(index)")
        
        if let player = players[index] {
            player.pause()
            cleanupObservers(for: index)
            player.replaceCurrentItem(with: nil)
            players.removeValue(forKey: index)
            playerUrls.removeValue(forKey: index)
            
            // Update state if this was the active video
            if activeVideoIndex == index {
                currentState = .idle
                activeVideoIndex = nil
            }
            
            // Cancel any preload task
            preloadTasks[index]?.cancel()
            preloadTasks.removeValue(forKey: index)
            
            // Clear states
            bufferingStates[index] = nil
            bufferingProgress[index] = nil
            playerStates[index] = nil
            preloadStates[index] = nil
            
            print("✅ CLEANUP: Successfully cleaned up video at index \(index)")
        }
    }

    func prepareForTransition(from currentIndex: Int, to targetIndex: Int) {
        print("🔄 TRANSITION: Starting transition from \(currentIndex) to \(targetIndex)")
        
        // Cancel any existing transition
        transitionTask?.cancel()
        
        // Start new transition
        isTransitioning = true
        transitionTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Update state
            await MainActor.run {
                self.currentState = .loading(index: targetIndex)
                self.activeVideoIndex = targetIndex
            }
            
            // Calculate keep range (include more videos for smoother navigation)
            let keepRange = KeepRange(
                start: min(currentIndex, targetIndex) - 2,
                end: max(currentIndex, targetIndex) + 2
            )
            
            // Cleanup distant players
            for index in self.players.keys where !keepRange.contains(index) {
                self.performCleanup(for: index)
            }
            
            // Ensure we're on main actor for state updates
            await MainActor.run {
                self.isTransitioning = false
            }
            
            print("✅ TRANSITION: Completed transition preparation to \(targetIndex)")
        }
    }
    
    func finishTransition(at index: Int) {
        print("✅ TRANSITION: Finishing transition to index \(index)")
        
        // Ensure we're in the correct state
        guard case .playing(let currentIndex) = currentState, currentIndex == index else {
            currentState = .playing(index: index)
            return
        }
        
        // Update active video index
        activeVideoIndex = index
        
        // Schedule cleanup of distant videos and preload new ones
        Task { @MainActor in
            // Keep a larger window of videos around the current index
            let keepRange = KeepRange(
                start: max(0, index - preloadWindowSize),
                end: index + preloadWindowSize
            )
            
            // Only cleanup videos well outside the keep range
            let cleanupThreshold = preloadWindowSize * 2
            for videoIndex in players.keys where videoIndex < keepRange.start - cleanupThreshold || videoIndex > keepRange.end + cleanupThreshold {
                performCleanup(for: videoIndex)
            }
            
            // Check if we need to preload more videos forward
            let remainingForward = keepRange.end - index
            if remainingForward <= preloadTriggerThreshold {
                // Trigger preload of next batch of videos in groups of 3
                for batchStart in stride(from: keepRange.end + 1, to: keepRange.end + preloadWindowSize + 1, by: 3) {
                    let batchEnd = min(batchStart + 2, keepRange.end + preloadWindowSize)
                    for i in batchStart...batchEnd {
                        if let url = playerUrls[i] {
                            do {
                                try await preloadVideo(url: url, forIndex: i)
                            } catch {
                                print("❌ PRELOAD ERROR: Failed to preload video at index \(i): \(error.localizedDescription)")
                            }
                        }
                    }
                    // Small delay between batches
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            
            // Check if we need to preload more videos backward
            let remainingBackward = index - keepRange.start
            if remainingBackward <= preloadTriggerThreshold {
                // Trigger preload of previous batch of videos in groups of 3
                for batchStart in stride(from: keepRange.start - 1, through: max(0, keepRange.start - preloadWindowSize), by: -3) {
                    let batchEnd = max(batchStart - 2, max(0, keepRange.start - preloadWindowSize))
                    for i in (batchEnd...batchStart).reversed() where i >= 0 {
                        if let url = playerUrls[i] {
                            do {
                                try await preloadVideo(url: url, forIndex: i)
                            } catch {
                                print("❌ PRELOAD ERROR: Failed to preload video at index \(i): \(error.localizedDescription)")
                            }
                        }
                    }
                    // Small delay between batches
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        
        print("✅ TRANSITION: Successfully finished transition to \(index)")
    }
    
    private func handleTimeUpdate(time: CMTime, for player: AVPlayer, at index: Int) {
        let seconds = CMTimeGetSeconds(time)
        print("⏱️ TIME: Video \(index) at \(seconds) seconds")
    }
    
    private func cleanupResourcesOutside(_ keepRange: KeepRange) {
        for (index, player) in players {
            if !keepRange.contains(index) {
                cleanupPlayer(at: index)
            }
        }
        print("🧹 CLEANUP: Cleaned up resources outside range \(keepRange.start)-\(keepRange.end)")
    }
    
    private func cleanupPlayer(at index: Int) {
        if let player = players[index] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            removePlayerObservers(for: player, at: index)
            players[index] = nil
            playerItems[index] = nil
            playerStates[index] = nil
            print("🧹 CLEANUP: Cleaned up player at index \(index)")
        }
    }
    
    private func cleanupAllResources() {
        for (index, _) in players {
            cleanupPlayer(at: index)
        }
        players.removeAll()
        playerItems.removeAll()
        playerStates.removeAll()
        print("🧹 CLEANUP: Cleaned up all resources")
    }

    func preservePlayerState(for index: Int) {
        guard let player = players[index] else { return }
        preservedPlayers[index] = player
        preservedStates[index] = playerStates[index]
        preservedItems[index] = player.currentItem
        print("🎮 PLAYER: Preserved state for video at index \(index)")
    }
    
    func restorePlayerState(for index: Int) {
        if let player = preservedPlayers[index] {
            players[index] = player
            playerStates[index] = preservedStates[index]
            if let item = preservedItems[index] {
                player.replaceCurrentItem(with: item)
            }
            print("🎮 PLAYER: Restored state for video at index \(index)")
        }
    }

    private func retryLoadingIfNeeded(for index: Int) async {
        guard let player = players[index],
              let currentItem = player.currentItem,
              currentItem.status == .failed else {
            return
        }
        
        print("🔄 SYSTEM: Attempting to retry loading video \(index)")
        
        // Wait a bit before retrying
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        if let asset = currentItem.asset as? AVURLAsset {
            do {
                let newPlayerItem = try await videoCacheService.preloadVideo(url: asset.url)
                await MainActor.run {
                    player.replaceCurrentItem(with: newPlayerItem)
                    print("✅ SYSTEM: Successfully reloaded video \(index)")
                }
            } catch {
                print("❌ SYSTEM ERROR: Failed to reload video \(index): \(error.localizedDescription)")
            }
        }
    }

    func beginTransition(_ newTransition: TransitionState, completion: @escaping () -> Void) {
        // Cancel any pending transitions
        transitionQueue.removeAll()
        
        // If there's an active transition, cancel it
        if case .gesture(_, _) = transitionState {
            // Complete the current transition immediately
            isProcessingTransition = false
            transitionState = .none
        }
        
        // Start the new transition immediately
        transitionState = newTransition
        completion()
    }
    
    // Update findLeastSimilarVideo to store sorted queue
    func findLeastSimilarVideo(for boardVideos: [LikeTheseVideo], excluding: [String] = []) async throws -> LikeTheseVideo {
        // Add rate limiting
        if let lastFetch = lastFetchTime, 
           Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
            print("⏱️ Rate limit: Using cached results")
            // Return from cache if available
            if !sortedCandidates.isEmpty && nextVideoIndex < sortedCandidates.count {
                let nextCandidate = sortedCandidates[nextVideoIndex]
                if let video = videos.first(where: { $0.id == nextCandidate.videoId }) {
                    print("✅ Using cached video: \(video.id) at index \(nextVideoIndex)")
                    nextVideoIndex += 1
                    return video
                }
            }
        }
        
        lastFetchTime = Date()
        print("🔄 Rate limit passed, fetching new results")
        
        let candidateVideos = videos.filter { video in
            !boardVideos.contains { $0.id == video.id } && 
            !excluding.contains(video.id)
        }
        
        let data: [String: Any] = [
            "boardVideos": boardVideos.map { [
                "id": $0.id,
                "url": $0.url,
                "frameUrl": $0.frameUrl ?? $0.thumbnailUrl
            ]},
            "candidateVideos": candidateVideos.map { [
                "id": $0.id,
                "url": $0.url,
                "frameUrl": $0.frameUrl ?? $0.thumbnailUrl
            ]}
        ]
        
        let result = try await functions.httpsCallable("findLeastSimilarVideo").call(data)
        guard let response = result.data as? [String: Any],
              let chosenId = response["chosen"] as? String else {
            throw VideoError.invalidResponse
        }
        
        // Store sorted candidates if available
        if let sortedList = response["sortedCandidates"] as? [[String: Any]] {
            print("📊 Received \(sortedList.count) sorted candidates")
            self.sortedCandidates = sortedList.compactMap { candidate in
                guard let videoId = candidate["videoId"] as? String,
                      let distance = candidate["distance"] as? Double else {
                    return nil
                }
                return (videoId: videoId, distance: distance)
            }
            self.nextVideoIndex = 0
        }
        
        // Find the chosen video in our candidates
        guard let video = candidateVideos.first(where: { $0.id == chosenId }) else {
            print("❌ Chosen video \(chosenId) not found in candidates")
            throw VideoError.videoNotFound
        }
        
        print("✅ Found chosen video: \(video.id)")
        return video
    }
    
    // Add function to get next video from sorted queue
    func getNextSortedVideo(currentBoardVideos: [LikeTheseVideo]) async throws -> LikeTheseVideo {
        // If we've reached the end or have no sorted candidates, get a fresh list
        if nextVideoIndex >= sortedCandidates.count || sortedCandidates.isEmpty {
            let video = try await findLeastSimilarVideo(for: currentBoardVideos)
            // findLeastSimilarVideo will refresh sortedCandidates and reset nextVideoIndex
            return video
        }
        
        // Get next video from sorted list
        let nextCandidate = sortedCandidates[nextVideoIndex]
        guard let video = videos.first(where: { $0.id == nextCandidate.videoId }) else {
            throw VideoError.videoNotFound
        }
        
        // Increment index for next time
        nextVideoIndex += 1
        
        return video
    }
    
    // Add function to reset sorted queue
    func resetSortedQueue() {
        sortedCandidates = []
        nextVideoIndex = 0
    }
    
    private var lastFetchTime: Date?
    private let minimumFetchInterval: TimeInterval = 2.0 // 2 seconds
} 