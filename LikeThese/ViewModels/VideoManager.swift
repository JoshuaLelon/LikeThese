import Foundation
import AVKit
import os
import Network

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoManager")

enum VideoTransitionState {
    case none
    case transitioning(from: Int, to: Int)
    case playing(index: Int)
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

enum VideoManagerState {
    case idle
    case loading(index: Int)
    case playing(index: Int)
    case paused(index: Int)
    case buffering(index: Int, progress: Float)
    case error(index: Int, error: Error)
}

@MainActor
class VideoManager: NSObject, ObservableObject {
    // State tracking
    @Published private(set) var currentState: VideoManagerState = .idle
    @Published private(set) var activeVideoIndex: Int?
    @Published private(set) var isTransitioning = false
    
    // Existing properties
    private var players: [Int: AVPlayer] = [:]
    private var preloadedPlayers: [Int: AVPlayer] = [:]
    private var observers: [Int: NSKeyValueObservation] = [:]
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
    
    // Configuration
    private let preferredBufferDuration: TimeInterval = 10.0
    private let verificationTimeout: TimeInterval = 10.0
    private let minimumBufferDuration: TimeInterval = 3.0
    
    var onVideoComplete: ((Int) -> Void)?
    
    private var isTransitioningToPlayback = false
    
    private var transitionState: VideoTransitionState = .none
    private var keepRange: KeepRange?
    private var pendingCleanup = Set<Int>()
    
    // Add state tracking
    @Published private(set) var preloadStates: [Int: PreloadState] = [:]
    
    override init() {
        super.init()
        logger.info("📱 VideoManager initialized")
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            Task { @MainActor in
                self.isNetworkAvailable = path.status == .satisfied
                self.networkState = path.status == .satisfied ? "connected" : "disconnected"
                
                if path.status == .satisfied {
                    logger.info("🌐 NETWORK: Connection restored")
                    await self.retryFailedLoads()
                } else {
                    logger.info("🌐 NETWORK: Connection lost")
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func retryFailedLoads() async {
        logger.info("🔄 NETWORK: Retrying \(self.retryQueue.count) failed loads")
        let itemsToRetry = self.retryQueue
        self.retryQueue.removeAll()
        
        for item in itemsToRetry {
            do {
                logger.info("🔄 RETRY: Attempting to load video for index \(item.index)")
                try await preloadVideo(url: item.url, forIndex: item.index)
            } catch {
                logger.error("❌ RETRY ERROR: Failed to reload video \(item.index): \(error.localizedDescription)")
                // Add back to queue if still failing
                self.retryQueue.append(item)
            }
        }
    }
    
    func player(for index: Int) -> AVPlayer? {
        return players[index]
    }
    
    func preloadVideo(url: URL, forIndex index: Int) async throws {
        logger.info("🔄 PRELOAD: Starting preload for index \(index) with URL: \(url)")
        
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
                guard playerItem.asset.isPlayable else {
                    logger.error("❌ PRELOAD ERROR: Asset is not playable for index \(index)")
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
                    self.setupBuffering(for: player, at: index)
                    self.setupEndTimeObserver(for: player, at: index)
                    
                    // Update states
                    self.preloadStates[index] = .ready
                    if self.activeVideoIndex == index {
                        self.currentState = .paused(index: index)
                    }
                    
                    logger.info("✅ PRELOAD: Successfully preloaded video at index \(index)")
                }
            }
        } catch {
            logger.error("❌ PRELOAD ERROR: Failed to preload video \(index) after retries: \(error.localizedDescription)")
            
            // Add to retry queue if it's a network error
            if (error as NSError).domain == NSURLErrorDomain {
                self.retryQueue.append((index: index, url: url))
                logger.info("🔄 PRELOAD: Added to retry queue - index: \(index)")
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
                
                logger.info("🔄 RETRY: Attempt \(attempt) failed, retrying in \(delay) seconds")
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
    
    private func setupBuffering(for player: AVPlayer, at index: Int) {
        // Remove any existing observers for this index first
        cleanupObservers(for: index)
        
        // Set preferred buffer duration
        player.automaticallyWaitsToMinimizeStalling = true
        
        // Add periodic time observer for tracking playback progress
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  let currentItem = player.currentItem else { return }
            
            let currentTime = CMTimeGetSeconds(time)
            let duration = CMTimeGetSeconds(currentItem.duration)
            
            // Log progress every 10 seconds or when significant events occur
            if Int(currentTime) % 10 == 0 || currentTime == duration {
                logger.info("📊 PLAYBACK PROGRESS: Video \(index) at \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s (\(String(format: "%.1f%%", currentTime/duration * 100))% complete)")
            }
            
            // Check buffering state
            let loadedRanges = currentItem.loadedTimeRanges
            guard let firstRange = loadedRanges.first as? CMTimeRange else { return }
            
            let bufferedDuration = CMTimeGetSeconds(firstRange.duration)
            if bufferedDuration.isFinite {
                let progress = Float(bufferedDuration / self.preferredBufferDuration)
                Task { @MainActor in
                    self.bufferingProgress[index] = min(progress, 1.0)
                    logger.info("📊 BUFFER PROGRESS: Video \(index) buffered \(String(format: "%.1f", bufferedDuration))s (\(String(format: "%.0f", progress * 100))%)")
                }
            }
        }
        timeObservers[index] = (observer: timeObserver, player: player)
        
        // Observe buffering state
        let bufferingObserver = player.observe(\.currentItem?.status) { [weak self] player, _ in
            guard let self = self else { return }
            if let currentItem = player.currentItem {
                let isBuffering = currentItem.status != .readyToPlay
                Task { @MainActor in
                    self.bufferingStates[index] = isBuffering
                    
                    if currentItem.status == .failed {
                        logger.error("❌ PLAYBACK ERROR: Video \(index) failed to load: \(String(describing: currentItem.error))")
                        await self.retryLoadingIfNeeded(for: index)
                    } else {
                        logger.info("🎮 BUFFER STATE: Video \(index) buffering: \(isBuffering)")
                    }
                }
            }
        }
        observers[index] = bufferingObserver
    }
    
    private func retryLoadingIfNeeded(for index: Int) async {
        guard let player = players[index],
              let currentItem = player.currentItem,
              currentItem.status == .failed else {
            return
        }
        
        logger.info("🔄 SYSTEM: Attempting to retry loading video \(index)")
        
        // Wait a bit before retrying
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        if let asset = currentItem.asset as? AVURLAsset {
            do {
                let newPlayerItem = try await videoCacheService.preloadVideo(url: asset.url)
                await MainActor.run {
                    player.replaceCurrentItem(with: newPlayerItem)
                    logger.info("✅ SYSTEM: Successfully reloaded video \(index)")
                }
            } catch {
                logger.error("❌ SYSTEM ERROR: Failed to reload video \(index): \(error.localizedDescription)")
            }
        }
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
                        logger.info("✅ PLAYBACK SUCCESS: Video \(index) successfully started playing")
                        // Reset completion state when video starts playing from beginning
                        let currentTime = CMTimeGetSeconds(time)
                        if currentTime < 1.0 {
                            self.completedVideos.remove(index)
                            logger.info("🔄 COMPLETION STATE: Reset completion state for video \(index) - starting from beginning")
                        }
                    }
                case .paused:
                    stateStr = "paused"
                    if oldState != "paused" {
                        logger.info("✅ PLAYBACK SUCCESS: Video \(index) successfully paused")
                    }
                case .waitingToPlayAtSpecifiedRate:
                    stateStr = "buffering"
                    if oldState != "buffering" {
                        logger.info("⏳ PLAYBACK WAIT: Video \(index) waiting to play (possibly buffering)")
                    }
                @unknown default:
                    stateStr = "unknown"
                    if oldState != "unknown" {
                        logger.info("⚠️ PLAYBACK WARNING: Video \(index) in unknown state")
                    }
                }
                
                if oldState != stateStr {
                    logger.info("🎮 PLAYER STATE: Video \(index) state changed: \(oldState ?? "none") -> \(stateStr)")
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
                if isNearEnd && 
                   player.timeControlStatus == .playing && 
                   !self.completedVideos.contains(index) && 
                   percentagePlayed >= 50 &&
                   currentItem.status == .readyToPlay {
                    
                    // Double check we're really at the end by comparing with duration
                    let actualTimeRemaining = duration - currentTime
                    guard actualTimeRemaining <= 0.15 else {
                        logger.info("⚠️ COMPLETION CHECK: False end detection for video \(index) - actual time remaining: \(String(format: "%.2f", actualTimeRemaining))s")
                        return
                    }
                    
                    // Mark video as completed
                    self.completedVideos.insert(index)
                    
                    // Explicit video completion logging
                    logger.info("🎬 VIDEO COMPLETED: Video at index \(index) has finished playing completely")
                    logger.info("📊 VIDEO COMPLETION STATS: Video \(index) reached its end after \(String(format: "%.1f", duration))s total playback time")
                    logger.info("📊 VIDEO COMPLETION STATS: Watched \(String(format: "%.1f", percentagePlayed))% of video")
                    logger.info("🔄 VIDEO COMPLETION ACTION: Video \(index) finished naturally while playing - initiating auto-advance sequence")
                    
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
        endTimeObservers[index] = (observer: observer, player: player)
        logger.info("👀 COMPLETION OBSERVER: Successfully set up video completion monitoring for index \(index)")
    }
    
    func prepareForPlayback() {
        isTransitioningToPlayback = true
        logger.info("🎮 TRANSITION: Preparing for video playback")
    }
    
    // Non-async wrapper for togglePlayPause
    func togglePlayPauseAction(index: Int) {
        logger.info("👆 TOGGLE: Requested for index \(index)")
        
        guard let player = players[index] else {
            logger.error("❌ PLAYBACK ERROR: No player found for index \(index)")
            return
        }
        
        Task { @MainActor in
            switch player.timeControlStatus {
            case .playing:
                player.pause()
                currentState = .paused(index: index)
                logger.info("⏸️ PLAYBACK: Paused video \(index)")
                
            case .paused:
                player.play()
                currentState = .playing(index: index)
                logger.info("▶️ PLAYBACK: Started playing video \(index)")
                
            case .waitingToPlayAtSpecifiedRate:
                currentState = .buffering(index: index, progress: bufferingProgress[index] ?? 0)
                logger.info("⏳ PLAYBACK: Video \(index) is buffering")
                
            @unknown default:
                logger.error("❌ PLAYBACK ERROR: Unknown player state for index \(index)")
            }
        }
    }
    
    func pauseAllExcept(index: Int) {
        logger.info("🔄 SYSTEM: Pausing all players except index \(index)")
        players.forEach { key, player in
            if key != index {
                player.pause()
                logger.info("🔄 SYSTEM: Paused player at index \(key)")
            } else if !completedVideos.contains(key) {
                // Only play if the video hasn't completed
                logger.info("🔄 SYSTEM: Playing video at index \(key)")
                player.play()
            } else {
                logger.info("⏸️ SYSTEM: Not playing completed video at index \(key)")
            }
        }
    }
    
    func cleanup(context: CleanupContext) {
        logger.info("🧹 CLEANUP: Starting cleanup with context: \(String(describing: context))")
        
        switch context {
        case .navigation(let fromIndex, let toIndex):
            // Keep videos in range of both indices
            let keepRange = KeepRange(
                start: max(0, min(fromIndex, toIndex) - 1),
                end: max(fromIndex, toIndex) + 1
            )
            
            // Only cleanup videos outside the keep range
            for index in players.keys {
                if !keepRange.contains(index) {
                    performCleanup(for: index)
                }
            }
            
            logger.info("🛡️ NAVIGATION CLEANUP: Keeping videos in range \(keepRange.start) to \(keepRange.end)")
            
        case .dismissal:
            // Clean everything up when dismissing
            logger.info("🧹 DISMISSAL CLEANUP: Cleaning up all resources")
            for index in players.keys {
                performCleanup(for: index)
            }
            players.removeAll()
            preloadedPlayers.removeAll()
            playerUrls.removeAll()
            preloadTasks.values.forEach { $0.cancel() }
            preloadTasks.removeAll()
            transitionTask?.cancel()
            transitionTask = nil
            
            // Reset all states
            currentState = .idle
            activeVideoIndex = nil
            isTransitioning = false
            
        case .error:
            // Clean up immediately on error
            logger.info("🧹 ERROR CLEANUP: Cleaning up due to error")
            for index in players.keys {
                performCleanup(for: index)
            }
            players.removeAll()
            preloadedPlayers.removeAll()
            playerUrls.removeAll()
            preloadTasks.values.forEach { $0.cancel() }
            preloadTasks.removeAll()
            transitionTask?.cancel()
            transitionTask = nil
            
            // Reset states but keep error state if we have an active video
            if let activeIndex = activeVideoIndex {
                currentState = .error(index: activeIndex, error: NSError(domain: "com.Gauntlet.LikeThese", code: -1, userInfo: [NSLocalizedDescriptionKey: "Playback error occurred"]))
            } else {
                currentState = .idle
            }
            isTransitioning = false
        }
        
        logger.info("✨ CLEANUP: Cleanup completed")
    }
    
    // Add public access to current player
    func currentPlayer(at index: Int) -> AVPlayer? {
        return players[index]
    }
    
    // Add seek to beginning helper
    func seekToBeginning(at index: Int) async {
        if let player = players[index] {
            logger.info("⏪ PLAYBACK ACTION: Seeking video \(index) to beginning")
            // Reset completion state when seeking to beginning
            completedVideos.remove(index)
            await player.seek(to: CMTime.zero)
            player.play()
            logger.info("▶️ PLAYBACK ACTION: Restarted video \(index) from beginning")
        }
    }
    
    private func cleanupObservers(for index: Int) {
        logger.info("🧹 CLEANUP: Starting observer cleanup for index \(index)")
        
        // Remove time observer if it exists
        if let observerData = timeObservers[index] {
            observerData.player.removeTimeObserver(observerData.observer)
            logger.info("🧹 CLEANUP: Removed time observer for index \(index)")
            timeObservers[index] = nil
        }
        
        // Remove KVO observer if it exists
        if let observer = observers[index] {
            observer.invalidate()
            observers[index] = nil
            logger.info("🧹 CLEANUP: Removed KVO observer for index \(index)")
        }
        
        // Remove end time observer if it exists
        if let observerData = endTimeObservers[index] {
            observerData.player.removeTimeObserver(observerData.observer)
            logger.info("🧹 CLEANUP: Removed end time observer for index \(index)")
            endTimeObservers[index] = nil
        }
        
        // Clear player item reference
        playerItems[index] = nil
        
        // Clear states
        bufferingStates[index] = nil
        bufferingProgress[index] = nil
        playerStates[index] = nil
        preloadStates[index] = nil
        
        logger.info("✨ CLEANUP: Completed observer cleanup for index \(index)")
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
        logger.info("🧹 CLEANUP: Performing cleanup for index \(index)")
        
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
            
            logger.info("✅ CLEANUP: Successfully cleaned up video at index \(index)")
        }
    }

    func prepareForTransition(from currentIndex: Int, to targetIndex: Int) {
        logger.info("🔄 TRANSITION: Starting transition from \(currentIndex) to \(targetIndex)")
        
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
            
            // Calculate keep range
            let keepRange = KeepRange(
                start: min(currentIndex, targetIndex) - 1,
                end: max(currentIndex, targetIndex) + 1
            )
            
            // Cleanup distant players
            for index in self.players.keys where !keepRange.contains(index) {
                await self.performCleanup(for: index)
            }
            
            // Ensure we're on main actor for state updates
            await MainActor.run {
                self.isTransitioning = false
            }
            
            logger.info("✅ TRANSITION: Completed transition to \(targetIndex)")
        }
    }
    
    func finishTransition(at index: Int) {
        logger.info("✅ TRANSITION: Finished transition to index \(index)")
        transitionState = .playing(index: index)
    }
    
    private func setupObservers(for index: Int, player: AVPlayer) {
        // Setup time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = CMTimeGetSeconds(time)
            logger.info("⏱️ TIME: Video \(index) at \(seconds) seconds")
        }
        self.timeObservers[index] = (observer: timeObserver, player: player)
        
        // Setup end time observer
        let endTime = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let endObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) { [weak self] in
            guard let self else { return }
            logger.info("🎬 END: Video \(index) reached end")
            Task { @MainActor in
                self.onVideoComplete?(index)
            }
        }
        self.endTimeObservers[index] = (observer: endObserver, player: player)
        
        // Setup KVO observer for status changes
        let observer = player.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                switch player.timeControlStatus {
                case .playing:
                    logger.info("▶️ STATUS: Video \(index) is playing")
                case .paused:
                    logger.info("⏸️ STATUS: Video \(index) is paused")
                case .waitingToPlayAtSpecifiedRate:
                    logger.info("⏳ STATUS: Video \(index) is buffering")
                @unknown default:
                    logger.info("❓ STATUS: Video \(index) in unknown state")
                }
            }
        }
        self.observers[index] = observer
        
        logger.info("👀 OBSERVERS: Set up all observers for video \(index)")
    }
    
    // Add method to get active players
    func getActivePlayers() -> [Int] {
        Array(players.keys)
    }
} 