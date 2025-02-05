import Foundation
import AVKit
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoManager")

class VideoManager: ObservableObject {
    private var players: [Int: AVPlayer] = [:]
    private var preloadedPlayers: [Int: AVPlayer] = [:]
    private var observers: [Int: NSKeyValueObservation] = [:]
    private var endTimeObservers: [Int: Any] = [:]  // Store end-time observers
    private let videoCacheService = VideoCacheService.shared
    
    @Published private(set) var bufferingStates: [Int: Bool] = [:]
    @Published private(set) var bufferingProgress: [Int: Float] = [:]
    @Published private(set) var playerStates: [Int: String] = [:] // Track player states
    
    private let preferredBufferDuration: TimeInterval = 10.0 // Buffer 10 seconds ahead
    
    // Add completion handler
    var onVideoComplete: ((Int) -> Void)?
    
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
        // Set preferred buffer duration
        player.automaticallyWaitsToMinimizeStalling = true
        
        // Observe buffering state
        let observer = player.observe(\.currentItem?.isPlaybackLikelyToKeepUp) { [weak self] player, _ in
            guard let self = self else { return }
            let isBuffering = !(player.currentItem?.isPlaybackLikelyToKeepUp ?? true)
            DispatchQueue.main.async {
                self.bufferingStates[index] = isBuffering
                logger.debug("🎮 BUFFER STATE: Video \(index) buffering: \(isBuffering)")
                
                if let duration = player.currentItem?.duration.seconds,
                   let currentTime = player.currentItem?.currentTime().seconds {
                    let remaining = duration - currentTime
                    logger.debug("⏱️ PLAYBACK INFO: Video \(index) at \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s (\(String(format: "%.1f", remaining))s remaining)")
                }
            }
        }
        observers[index] = observer
        
        // Monitor buffering progress
        let timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] _ in
            guard let self = self,
                  let currentItem = player.currentItem else { return }
            
            let loadedRanges = currentItem.loadedTimeRanges
            guard let firstRange = loadedRanges.first as? CMTimeRange else { return }
            
            let bufferedDuration = CMTimeGetSeconds(firstRange.duration)
            let progress = Float(bufferedDuration / self.preferredBufferDuration)
            self.bufferingProgress[index] = min(progress, 1.0)
            logger.debug("📊 BUFFER PROGRESS: Video \(index) buffered \(String(format: "%.1f", bufferedDuration))s (\(String(format: "%.0f", progress * 100))%)")
        }
        
        // Monitor for playback errors
        let errorObserver = player.observe(\.currentItem?.error) { [weak self] player, _ in
            if let error = player.currentItem?.error {
                logger.error("❌ PLAYBACK ERROR: Video \(index) encountered error: \(error.localizedDescription)")
            }
        }
        
        observers[index] = observer
    }
    
    private func setupStateObserver(for player: AVPlayer, at index: Int) {
        let observer = player.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let state: String
                switch player.timeControlStatus {
                case .playing:
                    state = "playing"
                case .paused:
                    state = "paused"
                case .waitingToPlayAtSpecifiedRate:
                    state = "buffering"
                @unknown default:
                    state = "unknown"
                }
                logger.debug("🎮 PLAYER STATE: Video \(index) state changed to: \(state)")
                self.playerStates[index] = state
            }
        }
        observers[index] = observer
    }
    
    private func setupEndTimeObserver(for player: AVPlayer, at index: Int) {
        // Remove any existing observer
        if let existingObserver = endTimeObservers[index] {
            NotificationCenter.default.removeObserver(existingObserver)
            endTimeObservers.removeValue(forKey: index)
            logger.debug("🧹 SYSTEM: Removed existing end time observer for index \(index)")
        }
        
        // Add new observer
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            logger.debug("🎬 SYSTEM: Video at index \(index) reached end")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let player = self.players[index] else {
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
        do {
            let playerItem = try await videoCacheService.preloadVideo(url: url)
            await MainActor.run {
                let player = AVPlayer(playerItem: playerItem)
                preloadedPlayers[index] = player
                setupBuffering(for: player, at: index)
                setupEndTimeObserver(for: player, at: index)
                logger.debug("✅ SYSTEM: Successfully preloaded video for index \(index)")
            }
        } catch {
            logger.error("❌ SYSTEM ERROR: Failed to preload video: \(error.localizedDescription)")
        }
    }
    
    func togglePlayPause(index: Int) {
        guard let player = players[index] else { return }
        
        if player.timeControlStatus == .playing {
            logger.debug("👤 USER ACTION: Manually paused video at index \(index)")
            player.pause()
        } else {
            logger.debug("👤 USER ACTION: Manually played video at index \(index)")
            player.play()
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
        if let player = players[index] {
            if let currentTime = player.currentItem?.currentTime().seconds {
                logger.debug("⏱️ CLEANUP INFO: Video \(index) stopped at \(String(format: "%.1f", currentTime))s")
            }
        }
        players[index]?.pause()
        observers[index]?.invalidate()
        observers.removeValue(forKey: index)
        
        // Remove end time observer
        if let observer = endTimeObservers[index] {
            NotificationCenter.default.removeObserver(observer)
            endTimeObservers.removeValue(forKey: index)
        }
        
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
} 