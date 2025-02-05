import Foundation
import AVKit
import os
import Network

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoManager")

class VideoManager: NSObject, ObservableObject {
    private var players: [Int: AVPlayer] = [:]
    private var preloadedPlayers: [Int: AVPlayer] = [:]
    private var observers: [Int: NSKeyValueObservation] = [:]
    private var timeObservers: [Int: (observer: Any, player: AVPlayer)] = [:]  // Track observers with their players
    private var endTimeObservers: [Int: (observer: Any, player: AVPlayer)] = [:]  // Track end-time observers with their players
    private var playerItems: [Int: AVPlayerItem] = [:]
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
    
    override init() {
        super.init()
        logger.debug("📱 VideoManager initialized")
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            Task { @MainActor in
                self.isNetworkAvailable = path.status == .satisfied
                self.networkState = path.status == .satisfied ? "connected" : "disconnected"
                
                if path.status == .satisfied {
                    logger.debug("🌐 NETWORK: Connection restored")
                    await self.retryFailedLoads()
                } else {
                    logger.debug("🌐 NETWORK: Connection lost")
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func retryFailedLoads() async {
        logger.debug("🔄 NETWORK: Retrying \(self.retryQueue.count) failed loads")
        let itemsToRetry = self.retryQueue
        self.retryQueue.removeAll()
        
        for item in itemsToRetry {
            do {
                logger.debug("🔄 RETRY: Attempting to load video for index \(item.index)")
                await preloadVideo(url: item.url, forIndex: item.index)
            } catch {
                logger.error("❌ RETRY ERROR: Failed to reload video \(item.index): \(error.localizedDescription)")
                // Add back to queue if still failing
                self.retryQueue.append(item)
            }
        }
    }
    
    func player(for index: Int) -> AVPlayer {
        if let existingPlayer = players[index] {
            logger.debug("🎮 PLAYER ACCESS: Using existing player for index \(index)")
            if let currentItem = existingPlayer.currentItem {
                logger.debug("📊 PLAYER STATUS: Video \(index) ready to play: \(currentItem.status == .readyToPlay)")
                if currentItem.status == .failed {
                    logger.debug("⚠️ PLAYER WARNING: Player item failed for index \(index), will attempt recovery")
                    // Recovery will happen in VideoPlayerView
                }
            } else {
                logger.debug("⚠️ PLAYER WARNING: Player exists but has no item for index \(index)")
                // Try to recover the player item
                if let item = playerItems[index] {
                    logger.debug("🔄 PLAYER RECOVERY: Restoring player item for index \(index)")
                    existingPlayer.replaceCurrentItem(with: item)
                } else if let url = playerUrls[index] {
                    // If we have the URL but no item, try to recreate the item
                    Task {
                        do {
                            let playerItem = try await videoCacheService.preloadVideo(url: url)
                            await MainActor.run {
                                existingPlayer.replaceCurrentItem(with: playerItem)
                                logger.debug("🔄 PLAYER RECOVERY: Recreated player item for index \(index)")
                            }
                        } catch {
                            logger.error("❌ PLAYER ERROR: Failed to recover player item for index \(index)")
                        }
                    }
                }
            }
            return existingPlayer
        }
        
        // If we have a preloaded player, use it
        if let preloadedPlayer = preloadedPlayers[index] {
            logger.debug("🎮 Using preloaded player for index \(index)")
            players[index] = preloadedPlayer
            preloadedPlayers.removeValue(forKey: index)
            
            // Store the player item for potential recovery
            if let item = preloadedPlayer.currentItem {
                playerItems[index] = item
                logger.debug("📦 PLAYER SETUP: Stored player item for index \(index)")
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
        
        logger.debug("🎮 Creating new player for index \(index)")
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
                logger.debug("📊 PLAYBACK PROGRESS: Video \(index) at \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s (\(String(format: "%.1f%%", currentTime/duration * 100))% complete)")
            }
            
            // Check buffering state
            let loadedRanges = currentItem.loadedTimeRanges
            guard let firstRange = loadedRanges.first as? CMTimeRange else { return }
            
            let bufferedDuration = CMTimeGetSeconds(firstRange.duration)
            if bufferedDuration.isFinite {
                let progress = Float(bufferedDuration / self.preferredBufferDuration)
                self.bufferingProgress[index] = min(progress, 1.0)
                logger.debug("📊 BUFFER PROGRESS: Video \(index) buffered \(String(format: "%.1f", bufferedDuration))s (\(String(format: "%.0f", progress * 100))%)")
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
                        logger.debug("🎮 BUFFER STATE: Video \(index) buffering: \(isBuffering)")
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
        
        logger.debug("🔄 SYSTEM: Attempting to retry loading video \(index)")
        
        // Wait a bit before retrying
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        if let asset = await currentItem.asset as? AVURLAsset {
            do {
                let newPlayerItem = try await videoCacheService.preloadVideo(url: asset.url)
                await MainActor.run {
                    player.replaceCurrentItem(with: newPlayerItem)
                    logger.debug("✅ SYSTEM: Successfully reloaded video \(index)")
                }
            } catch {
                logger.error("❌ SYSTEM ERROR: Failed to reload video \(index): \(error.localizedDescription)")
            }
        }
    }
    
    private func setupStateObserver(for player: AVPlayer, at index: Int) {
        // Use periodic time observer to check state
        let interval = CMTime(value: 1, timescale: 10) // 0.1 seconds with integer values
        let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            
            let newState = player.timeControlStatus
            let oldState = self.playerStates[index]
            
            let stateStr: String
            switch newState {
            case .playing:
                stateStr = "playing"
                if oldState != "playing" {
                    logger.debug("✅ PLAYBACK SUCCESS: Video \(index) successfully started playing")
                }
            case .paused:
                stateStr = "paused"
                if oldState != "paused" {
                    logger.debug("✅ PLAYBACK SUCCESS: Video \(index) successfully paused")
                }
            case .waitingToPlayAtSpecifiedRate:
                stateStr = "buffering"
                if oldState != "buffering" {
                    logger.debug("⏳ PLAYBACK WAIT: Video \(index) waiting to play (possibly buffering)")
                }
            @unknown default:
                stateStr = "unknown"
                if oldState != "unknown" {
                    logger.debug("⚠️ PLAYBACK WARNING: Video \(index) in unknown state")
                }
            }
            
            if oldState != stateStr {
                logger.debug("🎮 PLAYER STATE: Video \(index) state changed: \(oldState ?? "none") -> \(stateStr)")
                self.playerStates[index] = stateStr
            }
        }
        
        // Store the observer
        endTimeObservers[index] = (observer: observer, player: player)
    }
    
    private func setupEndTimeObserver(for player: AVPlayer, at index: Int) {
        // Add observer for video end
        let observer = player.addBoundaryTimeObserver(forTimes: [NSValue(time: player.currentItem?.duration ?? .zero)],
                                                    queue: .main) { [weak self] in
            guard let self = self else { return }
            logger.debug("🎬 SYSTEM: Video at index \(index) reached end")
            
            // Log final video stats
            if let currentItem = player.currentItem {
                let duration = CMTimeGetSeconds(currentItem.duration)
                logger.debug("📊 VIDEO COMPLETION: Video \(index) completed after \(String(format: "%.1f", duration))s")
            }
            
            // Check if video should auto-advance
            if player.timeControlStatus == .playing {
                logger.debug("🤖 AUTO ACTION: Triggering auto-advance from index \(index)")
                self.onVideoComplete?(index)
            } else {
                logger.debug("⏸️ SYSTEM: Player \(index) is paused, skipping auto-advance")
            }
        }
        
        endTimeObservers[index] = (observer: observer, player: player)
        logger.debug("🎬 SYSTEM: Added end time observer for index \(index)")
    }
    
    @MainActor
    func preloadVideo(url: URL, forIndex index: Int) async {
        playerUrls[index] = url // Store URL for recovery
        logger.debug("🔄 SYSTEM: Preloading video for index \(index)")
        
        guard isNetworkAvailable else {
            logger.debug("🌐 NETWORK: No connection, queueing video \(index) for later")
            retryQueue.append((index: index, url: url))
            return
        }
        
        do {
            let playerItem = try await videoCacheService.preloadVideo(url: url)
            
            // Load essential asset properties
            let asset = await playerItem.asset
            
            // Use modern async/await API for loading asset properties
            if #available(iOS 16.0, *) {
                try await asset.load(.tracks, .duration, .isPlayable)
                
                // Load video track properties if available
                if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                    try await videoTrack.load(.naturalSize, .preferredTransform)
                    logger.debug("✅ SYSTEM: Successfully loaded video track properties for index \(index)")
                }
            } else {
                // Fallback for older iOS versions
                let assetKeys = ["tracks", "duration", "playable"]
                for key in assetKeys {
                    try await asset.loadValuesAsynchronously(forKeys: [key])
                }
                
                if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                    let trackKeys = ["naturalSize", "preferredTransform"]
                    for key in trackKeys {
                        try await videoTrack.loadValuesAsynchronously(forKeys: [key])
                    }
                    logger.debug("✅ SYSTEM: Successfully loaded video track properties for index \(index)")
                }
            }
            
            await MainActor.run {
                let player = AVPlayer(playerItem: playerItem)
                preloadedPlayers[index] = player
                setupBuffering(for: player, at: index)
                setupEndTimeObserver(for: player, at: index)
                logger.debug("✅ SYSTEM: Successfully preloaded video for index \(index)")
            }
        } catch {
            logger.error("❌ SYSTEM ERROR: Failed to preload video: \(error.localizedDescription)")
            if isNetworkAvailable {
                // Only queue for retry if it wasn't a network issue
                retryQueue.append((index: index, url: url))
            }
        }
    }
    
    // Non-async wrapper for togglePlayPause
    func togglePlayPauseAction(index: Int) {
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
            logger.debug("👤 USER ACTION: Manual pause requested for video \(index)")
            // Add detailed user action logging
            if let currentItem = player.currentItem {
                let currentTime = CMTimeGetSeconds(currentItem.currentTime())
                let duration = CMTimeGetSeconds(currentItem.duration)
                logger.debug("📊 USER STATS: Video \(index) paused at \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s (\(String(format: "%.1f%%", currentTime/duration * 100))% watched)")
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
            logger.debug("👤 USER ACTION: Manual play requested for video \(index)")
            // Add detailed user action logging
            if let currentItem = player.currentItem {
                let currentTime = CMTimeGetSeconds(currentItem.currentTime())
                let duration = CMTimeGetSeconds(currentItem.duration)
                logger.debug("📊 USER STATS: Video \(index) resumed at \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s (\(String(format: "%.1f%%", currentTime/duration * 100))% watched)")
            }
            
            if let currentItem = player.currentItem {
                switch currentItem.status {
                case .readyToPlay:
                    logger.debug("✅ PLAYBACK INFO: Video \(index) is ready to play")
                    // Ensure proper playback rate and play
                    player.rate = 1.0
                    player.play()
                    
                    // Verify play state and handle failure
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    if player.timeControlStatus != .playing {
                        logger.error("❌ PLAYBACK ERROR: Video \(index) failed to start playing")
                        // Try alternative play method
                        let currentTime = currentItem.currentTime()
                        do {
                            try await player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        } catch {
                            logger.error("❌ PLAYBACK ERROR: Seek failed - \(error.localizedDescription)")
                        }
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
        logger.debug("🔄 SYSTEM: Pausing all players except index \(index)")
        players.forEach { key, player in
            if key != index {
                player.pause()
                logger.debug("🔄 SYSTEM: Paused player at index \(key)")
            } else {
                logger.debug("🔄 SYSTEM: Playing video at index \(key)")
                player.play()
            }
        }
    }
    
    func cleanupVideo(for index: Int) {
        logger.debug("🧹 CLEANUP: Starting cleanup for video \(index)")
        
        // Store the player item before cleanup if it exists
        if let player = players[index], let item = player.currentItem {
            playerItems[index] = item
            logger.debug("🔄 CLEANUP: Stored player item for index \(index) for potential recovery")
        }
        
        // Don't remove playerUrls[index] to allow for recovery
        
        // Cleanup observers first
        cleanupObservers(for: index)
        
        // Then cleanup player
        if let player = players[index] {
            // Pause playback
            player.pause()
            
            // Don't remove the player item immediately to allow for recovery during swipes
            // player.replaceCurrentItem(with: nil)
            
            // Remove player
            players.removeValue(forKey: index)
            logger.debug("🧹 CLEANUP: Removed player for index \(index)")
        }
        
        // Remove from preloaded players if exists
        if preloadedPlayers.removeValue(forKey: index) != nil {
            logger.debug("🧹 CLEANUP: Removed preloaded player for index \(index)")
        }
        
        logger.debug("✨ CLEANUP: Completed cleanup for video \(index)")
    }
    
    func cleanupPreloadedVideos() {
        preloadedPlayers.removeAll()
    }
    
    // Add public access to current player
    func currentPlayer(at index: Int) -> AVPlayer? {
        return players[index]
    }
    
    // Add seek to beginning helper
    func seekToBeginning(at index: Int) async {
        if let player = players[index] {
            logger.debug("⏪ PLAYBACK ACTION: Seeking video \(index) to beginning")
            await player.seek(to: CMTime.zero)
            player.play()
            logger.debug("▶️ PLAYBACK ACTION: Restarted video \(index) from beginning")
        }
    }
    
    private func cleanupObservers(for index: Int) {
        logger.debug("🧹 CLEANUP: Starting observer cleanup for index \(index)")
        
        // Remove time observer if it exists
        if let observerData = timeObservers[index] {
            observerData.player.removeTimeObserver(observerData.observer)
            logger.debug("🧹 CLEANUP: Removed time observer for index \(index)")
            timeObservers[index] = nil
        }
        
        // Remove KVO observer if it exists
        if let observer = observers[index] {
            observer.invalidate()
            observers[index] = nil
            logger.debug("🧹 CLEANUP: Removed KVO observer for index \(index)")
        }
        
        // Remove end time observer if it exists
        if let observerData = endTimeObservers[index] {
            observerData.player.removeTimeObserver(observerData.observer)
            logger.debug("🧹 CLEANUP: Removed end time observer for index \(index)")
            endTimeObservers[index] = nil
        }
        
        // Clear player item reference
        playerItems[index] = nil
        
        // Don't clear playerUrls[index] to allow for recovery
        logger.debug("✨ CLEANUP: Completed observer cleanup for index \(index)")
    }
    
    // Add public method to check distant players
    func getDistantPlayers(from currentIndex: Int) -> [Int] {
        // Only consider players more than 1 position away to keep adjacent videos ready
        return players.keys.filter { abs($0 - currentIndex) > 1 }
    }
} 