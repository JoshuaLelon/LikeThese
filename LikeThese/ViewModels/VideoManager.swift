import Foundation
import AVKit
import os
import Network

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoManager")

class VideoManager: ObservableObject {
    private var players: [Int: AVPlayer] = [:]
    private var preloadedPlayers: [Int: AVPlayer] = [:]
    private var observers: [Int: NSKeyValueObservation] = [:]
    private var timeObservers: [Int: (player: AVPlayer, observer: Any)] = [:] // Track which observer belongs to which player
    private var endTimeObservers: [Int: Any] = [:]  // Store end-time observers
    private let videoCacheService = VideoCacheService.shared
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private var retryQueue: [(index: Int, url: URL)] = []
    
    @Published private(set) var bufferingStates: [Int: Bool] = [:]
    @Published private(set) var bufferingProgress: [Int: Float] = [:]
    @Published private(set) var playerStates: [Int: String] = [:] // Track player states
    @Published private(set) var networkState: String = "unknown"
    
    private let preferredBufferDuration: TimeInterval = 10.0 // Buffer 10 seconds ahead
    
    // Add completion handler
    var onVideoComplete: ((Int) -> Void)?
    
    init() {
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
            }
            return existingPlayer
        }
        
        // If we have a preloaded player, use it
        if let preloadedPlayer = preloadedPlayers[index] {
            logger.debug("🎮 Using preloaded player for index \(index)")
            players[index] = preloadedPlayer
            preloadedPlayers.removeValue(forKey: index)
            setupBuffering(for: preloadedPlayer, at: index)
            setupEndTimeObserver(for: preloadedPlayer, at: index)
            setupStateObserver(for: preloadedPlayer, at: index)
            return preloadedPlayer
        }
        
        logger.debug("🎮 Creating new player for index \(index)")
        let player = AVPlayer()
        players[index] = player
        setupBuffering(for: player, at: index)
        setupEndTimeObserver(for: player, at: index)
        setupStateObserver(for: player, at: index)
        return player
    }
    
    private func setupBuffering(for player: AVPlayer, at index: Int) {
        // Cleanup any existing observers first
        cleanupObservers(for: index)
        
        // Set preferred buffer duration
        player.automaticallyWaitsToMinimizeStalling = true
        
        // Store time observer with its player reference
        let timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] _ in
            guard let self = self,
                  let currentItem = player.currentItem else { return }
            
            let loadedRanges = currentItem.loadedTimeRanges
            guard let firstRange = loadedRanges.first as? CMTimeRange else { return }
            
            let bufferedDuration = CMTimeGetSeconds(firstRange.duration)
            if bufferedDuration.isFinite {
                let progress = Float(bufferedDuration / self.preferredBufferDuration)
                self.bufferingProgress[index] = min(progress, 1.0)
                logger.debug("📊 BUFFER PROGRESS: Video \(index) buffered \(String(format: "%.1f", bufferedDuration))s (\(String(format: "%.0f", progress * 100))%)")
            }
        }
        timeObservers[index] = (player: player, observer: timeObserver)
        
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
                        let duration = currentItem.duration
                        let currentTime = currentItem.currentTime()
                        if duration.isValid && currentTime.isValid {
                            let durationSeconds = CMTimeGetSeconds(duration)
                            let currentSeconds = CMTimeGetSeconds(currentTime)
                            if durationSeconds.isFinite && currentSeconds.isFinite {
                                let remaining = durationSeconds - currentSeconds
                                logger.debug("⏱️ PLAYBACK INFO: Video \(index) at \(String(format: "%.1f", currentSeconds))s/\(String(format: "%.1f", durationSeconds))s (\(String(format: "%.1f", remaining))s remaining)")
                            }
                        }
                    }
                }
            }
        }
        observers[index] = bufferingObserver
        
        // Store error observer
        let errorObserver = player.observe(\.currentItem?.error) { [weak self] player, _ in
            guard let self = self else { return }
            if let error = player.currentItem?.error {
                logger.error("❌ PLAYBACK ERROR: Video \(index) encountered error: \(error.localizedDescription)")
                Task { @MainActor in
                    await self.retryLoadingIfNeeded(for: index)
                }
            }
        }
        observers[index] = errorObserver
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
        
        if let asset = currentItem.asset as? AVURLAsset {
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
        endTimeObservers[index] = observer
    }
    
    private func setupEndTimeObserver(for player: AVPlayer, at index: Int) {
        // Remove any existing observer first
        cleanupObservers(for: index)
        
        // Add new observer
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            logger.debug("🎬 SYSTEM: Video at index \(index) reached end")
            
            Task { @MainActor in
                guard let player = self.players[index] else {
                    logger.error("❌ SYSTEM ERROR: Player not found for index \(index)")
                    return
                }
                
                if player.timeControlStatus == .paused {
                    logger.debug("⏸️ SYSTEM: Player \(index) is paused, skipping auto-advance")
                    return
                }
                
                logger.debug("🤖 AUTO ACTION: Triggering auto-advance from index \(index)")
                self.onVideoComplete?(index)
            }
        }
        
        endTimeObservers[index] = observer
        logger.debug("🎬 SYSTEM: Added end time observer for index \(index)")
    }
    
    func preloadVideo(url: URL, forIndex index: Int) async {
        logger.debug("🔄 SYSTEM: Preloading video for index \(index)")
        
        guard isNetworkAvailable else {
            logger.debug("🌐 NETWORK: No connection, queueing video \(index) for later")
            retryQueue.append((index: index, url: url))
            return
        }
        
        do {
            let playerItem = try await videoCacheService.preloadVideo(url: url)
            
            // Load essential asset properties first
            let asset = playerItem.asset
            let assetKeys: [String] = ["tracks", "duration", "playable"]
            try await asset.loadValuesAsynchronously(forKeys: assetKeys)
            
            // Then load video track properties if available
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let trackKeys: [String] = ["naturalSize", "preferredTransform"]
                try await videoTrack.loadValuesAsynchronously(forKeys: trackKeys)
                logger.debug("✅ SYSTEM: Successfully loaded video track properties for index \(index)")
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
                        try? await player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
        
        // Cleanup observers first
        cleanupObservers(for: index)
        
        // Then cleanup player
        if let player = players[index] {
            if let currentTime = player.currentItem?.currentTime().seconds {
                logger.debug("⏱️ CLEANUP INFO: Video \(index) stopped at \(String(format: "%.1f", currentTime))s")
            }
            
            // Pause playback
            player.pause()
            
            // Remove the player's item to cancel any pending loads
            player.replaceCurrentItem(with: nil)
        }
        
        // Remove player and state
        players.removeValue(forKey: index)
        preloadedPlayers.removeValue(forKey: index)
        bufferingStates.removeValue(forKey: index)
        bufferingProgress.removeValue(forKey: index)
        playerStates.removeValue(forKey: index)
        
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
        // Cleanup KVO observers
        observers[index]?.invalidate()
        observers.removeValue(forKey: index)
        
        // Cleanup time observers using the correct player instance
        if let timeObserverPair = timeObservers[index] {
            timeObserverPair.player.removeTimeObserver(timeObserverPair.observer)
            timeObservers.removeValue(forKey: index)
            logger.debug("🧹 CLEANUP: Removed time observer for index \(index)")
        }
        
        logger.debug("🧹 CLEANUP: Removed all observers for index \(index)")
    }
} 