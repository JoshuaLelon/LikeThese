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
            logger.debug("🎮 Using existing player for index \(index)")
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
        }
        
        // Store time observer for cleanup
        player.currentItem?.preferredForwardBufferDuration = preferredBufferDuration
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
                logger.debug("🎮 Player \(index) state changed to: \(state)")
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
            logger.debug("🎬 Removed existing end time observer for index \(index)")
        }
        
        // Add new observer
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            logger.debug("🎬 Video at index \(index) finished playing")
            
            // Ensure we're on main thread and player exists
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let player = self.players[index] else {
                    logger.error("❌ Player not found for index \(index)")
                    return
                }
                
                // Don't auto-advance if player is paused
                if player.timeControlStatus == .paused {
                    logger.debug("⏸️ Player \(index) is paused, not auto-advancing")
                    return
                }
                
                logger.debug("⏭️ Auto-advancing from index \(index)")
                self.onVideoComplete?(index)
            }
        }
        
        endTimeObservers[index] = observer
        logger.debug("🎬 Added end time observer for index \(index)")
    }
    
    func preloadVideo(url: URL, forIndex index: Int) async {
        logger.debug("🔄 Preloading video for index \(index)")
        do {
            let playerItem = try await videoCacheService.preloadVideo(url: url)
            await MainActor.run {
                let player = AVPlayer(playerItem: playerItem)
                preloadedPlayers[index] = player
                setupBuffering(for: player, at: index)
                setupEndTimeObserver(for: player, at: index)
                logger.debug("✅ Successfully preloaded video for index \(index)")
            }
        } catch {
            logger.error("❌ Failed to preload video: \(error.localizedDescription)")
        }
    }
    
    func togglePlayPause(index: Int) {
        guard let player = players[index] else { return }
        
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
    
    func pauseAllExcept(index: Int) {
        logger.debug("⏸️ Pausing all players except index \(index)")
        players.forEach { key, player in
            if key != index {
                player.pause()
                logger.debug("⏸️ Paused player at index \(key)")
            } else {
                logger.debug("▶️ Playing video at index \(key)")
                player.play()
            }
        }
    }
    
    func cleanupVideo(for index: Int) {
        logger.debug("🧹 Cleaning up video at index \(index)")
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
            await player.seek(to: CMTime.zero)
            player.play()
        }
    }
} 