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

@MainActor
class VideoManager: NSObject, ObservableObject {
    private var players: [Int: AVPlayer] = [:]
    private var preloadedPlayers: [Int: AVPlayer] = [:]
    private var observers: [Int: NSKeyValueObservation] = [:]
    private var timeObservers: [Int: (observer: Any, player: AVPlayer)] = [:]  // Track observers with their players
    private var endTimeObservers: [Int: (observer: Any, player: AVPlayer)] = [:]  // Track end-time observers with their players
    private var playerItems: [Int: AVPlayerItem] = [:]
    private var completedVideos: Set<Int> = [] // Track which videos have completed
    private let videoCacheService = VideoCacheService.shared
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private var retryQueue: [(index: Int, url: URL)] = []
    private var playerUrls: [Int: URL] = [:] // Track URLs for recovery
    
    @Published private(set) var bufferingStates: [Int: Bool] = [:]
    @Published private(set) var bufferingProgress: [Int: Float] = [:]
    @Published private(set) var playerStates: [Int: String] = [:] // Track player states
    @Published private(set) var networkState: String = "unknown"
    
    private let preferredBufferDuration: TimeInterval = 10.0 // Buffer 10 seconds ahead
    
    // Add completion handler
    var onVideoComplete: ((Int) -> Void)?
    
    private var isTransitioningToPlayback = false
    
    private var transitionState: VideoTransitionState = .none
    private var keepRange: KeepRange?
    private var pendingCleanup = Set<Int>()
    
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
    
    func player(for index: Int) -> AVPlayer {
        logger.info("🎯 REQUEST: Getting player for index \(index)")
        logger.info("🔍 CURRENT STATE: Active players at indices: \(self.players.keys.sorted())")
        if let url = playerUrls[index] {
            logger.info("📺 VIDEO INFO: URL for index \(index): \(url)")
        }

        if let existingPlayer = players[index] {
            logger.info("🎮 PLAYER ACCESS: Using existing player for index \(index)")
            if let currentItem = existingPlayer.currentItem {
                logger.info("📊 PLAYER STATUS: Video \(index) ready to play: \(currentItem.status == .readyToPlay)")
                if let asset = currentItem.asset as? AVURLAsset {
                    logger.info("🔍 PLAYER DETAIL: Current URL for index \(index): \(asset.url)")
                }
                if currentItem.status == .failed {
                    logger.info("⚠️ PLAYER WARNING: Player item failed for index \(index), will attempt recovery")
                }
            } else {
                logger.info("⚠️ PLAYER WARNING: Player exists but has no item for index \(index)")
            }
            return existingPlayer
        }
        
        // If we have a preloaded player, use it
        if let preloadedPlayer = preloadedPlayers[index] {
            logger.info("🎮 Using preloaded player for index \(index)")
            players[index] = preloadedPlayer
            preloadedPlayers.removeValue(forKey: index)
            
            // Store the player item for potential recovery
            if let item = preloadedPlayer.currentItem {
                playerItems[index] = item
                logger.info("📦 PLAYER SETUP: Stored player item for index \(index)")
            }
            
            // Only setup observers if they don't exist
            if observers[index] == nil {
                setupBuffering(for: preloadedPlayer, at: index)
            }
            if endTimeObservers[index] == nil {
                setupEndTimeObserver(for: preloadedPlayer, at: index)
            }
            return preloadedPlayer
        }
        
        logger.info("🎮 Creating new player for index \(index)")
        let player = AVPlayer()
        players[index] = player
        
        // Clear any existing observers for this index before setting up new ones
        cleanupObservers(for: index)
        
        setupBuffering(for: player, at: index)
        setupEndTimeObserver(for: player, at: index)
        
        return player
    }
    
    private func setupBuffering(for player: AVPlayer, at index: Int) {
        // Remove any existing observers for this index first
        cleanupObservers(for: index)
        
        // Set preferred buffer duration
        player.automaticallyWaitsToMinimizeStalling = true
        
        // Add periodic time observer for tracking playback progress
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
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
            guard let self = self,
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
    
    func preloadVideo(url: URL, forIndex index: Int) async throws {
        logger.info("🔄 PRELOAD: Starting preload for index \(index)")
        
        // If player already exists and is ready, just return
        if let existingPlayer = players[index],
           let currentItem = existingPlayer.currentItem,
           currentItem.status == .readyToPlay {
            logger.info("⚠️ PRELOAD: Player already exists for index \(index)")
            return
        }
        
        do {
            // Store URL for recovery
            playerUrls[index] = url
            
            // Create new player item
            let playerItem = try await videoCacheService.preloadVideo(url: url)
            
            // Create new player
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = true
            
            // Store in preloaded players
            preloadedPlayers[index] = player
            playerItems[index] = playerItem
            
            // Setup observers
            setupBuffering(for: player, at: index)
            setupEndTimeObserver(for: player, at: index)
            
            logger.info("👀 OBSERVERS: Set up all observers for video \(index)")
            logger.info("✅ PRELOAD: Successfully preloaded video at index \(index)")
        } catch {
            logger.error("❌ PRELOAD ERROR: Failed to preload video \(index): \(error.localizedDescription)")
            if isNetworkAvailable {
                retryQueue.append((index: index, url: url))
            }
            throw error
        }
    }
    
    // Non-async wrapper for togglePlayPause
    func togglePlayPauseAction(index: Int) {
        logger.info("👆 TOGGLE: Requested for index \(index)")
        if let player = players[index], let asset = player.currentItem?.asset as? AVURLAsset {
            logger.info("🎮 TOGGLE INFO: Current URL: \(asset.url)")
        }
        Task { @MainActor in
            await togglePlayPause(index: index)
        }
    }

    @MainActor
    private func togglePlayPause(index: Int) async {
        guard let player = players[index] else {
            logger.error("❌ PLAYBACK ERROR: Cannot toggle play/pause - no player found for index \(index)")
            return
        }
        
        let currentState = player.timeControlStatus
        if currentState == .playing {
            logger.info("👤 USER ACTION: Manual pause requested for video \(index)")
            // Add detailed user action logging
            if let currentItem = player.currentItem {
                let currentTime = CMTimeGetSeconds(currentItem.currentTime())
                let duration = CMTimeGetSeconds(currentItem.duration)
                logger.info("📊 USER STATS: Video \(index) paused at \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s (\(String(format: "%.1f%%", currentTime/duration * 100))% watched)")
            }
            player.pause()
            
            // Verify the pause took effect and handle failure
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            if player.timeControlStatus != .paused {
                logger.error("❌ PLAYBACK ERROR: Video \(index) failed to pause")
                // Try pause again with rate setting
                player.rate = 0
                player.pause()
            }
        } else {
            logger.info("👤 USER ACTION: Manual play requested for video \(index)")
            // Add detailed user action logging
            if let currentItem = player.currentItem {
                let currentTime = CMTimeGetSeconds(currentItem.currentTime())
                let duration = CMTimeGetSeconds(currentItem.duration)
                logger.info("📊 USER STATS: Video \(index) resumed at \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s (\(String(format: "%.1f%%", currentTime/duration * 100))% watched)")
            }
            
            if let currentItem = player.currentItem {
                switch currentItem.status {
                case .readyToPlay:
                    logger.info("✅ PLAYBACK INFO: Video \(index) is ready to play")
                    // Ensure proper playback rate and play
                    player.rate = 1.0
                    player.play()
                    
                    // Verify play state and handle failure
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    if player.timeControlStatus != .playing {
                        logger.error("❌ PLAYBACK ERROR: Video \(index) failed to start playing")
                        // Try alternative play method
                        let currentTime = currentItem.currentTime()
                        await player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        player.rate = 1.0
                        player.play()
                    }
                case .failed:
                    logger.error("❌ PLAYBACK ERROR: Cannot play video \(index) - item failed: \(currentItem.error?.localizedDescription ?? "unknown error")")
                    // Attempt to recover
                    await retryLoadingIfNeeded(for: index)
                case .unknown:
                    logger.error("❌ PLAYBACK ERROR: Cannot play video \(index) - item status unknown")
                    // Wait for ready state
                    let observer = currentItem.observe(\.status) { item, _ in
                        if item.status == .readyToPlay {
                            player.play()
                        }
                    }
                    observers[index] = observer
                @unknown default:
                    logger.error("❌ PLAYBACK ERROR: Cannot play video \(index) - unexpected item status")
                }
            } else {
                logger.error("❌ PLAYBACK ERROR: Cannot play video \(index) - no current item")
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
            
        case .error:
            // Clean up immediately on error
            logger.info("🧹 ERROR CLEANUP: Cleaning up due to error")
            for index in players.keys {
                performCleanup(for: index)
            }
            players.removeAll()
            preloadedPlayers.removeAll()
            playerUrls.removeAll()
        }
        
        // Reset states
        transitionState = .none
        keepRange = nil
        pendingCleanup.removeAll()
        
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
        
        // Don't clear playerUrls[index] to allow for recovery
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
            logger.info("✅ CLEANUP: Successfully cleaned up video at index \(index)")
        }
    }

    func prepareForTransition(from currentIndex: Int, to targetIndex: Int) {
        logger.info("🔄 TRANSITION: Preparing transition from \(currentIndex) to \(targetIndex)")
        self.transitionState = .transitioning(from: currentIndex, to: targetIndex)
        cleanup(context: .navigation(from: currentIndex, to: targetIndex))
    }
    
    func finishTransition(at index: Int) {
        logger.info("✅ TRANSITION: Finished transition to index \(index)")
        transitionState = .playing(index: index)
    }
    
    private func setupObservers(for index: Int, player: AVPlayer) {
        // Setup time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            if let self {
                let seconds = CMTimeGetSeconds(time)
                logger.info("⏱️ TIME: Video \(index) at \(seconds) seconds")
            }
        }
        self.timeObservers[index] = (observer: timeObserver, player: player)
        
        // Setup end time observer
        let endTime = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let endObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) { [weak self] in
            if let self {
                logger.info("🎬 END: Video \(index) reached end")
                Task { @MainActor in
                    self.onVideoComplete?(index)
                }
            }
        }
        self.endTimeObservers[index] = (observer: endObserver, player: player)
        
        // Setup KVO observer for status changes
        let observer = player.observe(\.timeControlStatus) { [weak self] player, _ in
            if let self {
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
        }
        self.observers[index] = observer
        
        logger.info("👀 OBSERVERS: Set up all observers for video \(index)")
    }
    
    // Add method to get active players
    func getActivePlayers() -> [Int] {
        Array(players.keys)
    }
} 