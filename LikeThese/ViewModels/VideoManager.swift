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
    
    private let preferredBufferDuration: TimeInterval = 10.0 // Buffer 10 seconds ahead
    
    // Add completion handler
    var onVideoComplete: ((Int) -> Void)?
    
    func player(for index: Int) -> AVPlayer {
        if let existingPlayer = players[index] {
            return existingPlayer
        }
        
        // If we have a preloaded player, use it
        if let preloadedPlayer = preloadedPlayers[index] {
            players[index] = preloadedPlayer
            preloadedPlayers.removeValue(forKey: index)
            setupBuffering(for: preloadedPlayer, at: index)
            setupEndTimeObserver(for: preloadedPlayer, at: index)
            return preloadedPlayer
        }
        
        let player = AVPlayer()
        players[index] = player
        setupBuffering(for: player, at: index)
        setupEndTimeObserver(for: player, at: index)
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
    
    private func setupEndTimeObserver(for player: AVPlayer, at index: Int) {
        // Remove any existing observer
        if let existingObserver = endTimeObservers[index] {
            NotificationCenter.default.removeObserver(existingObserver)
            endTimeObservers.removeValue(forKey: index)
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
                      self.players[index] != nil else { return }
                self.onVideoComplete?(index)
            }
        }
        
        endTimeObservers[index] = observer
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
        players.forEach { key, player in
            if key != index {
                player.pause()
            } else {
                // Make sure the current video plays
                player.seek(to: .zero)
                player.play()
            }
        }
    }
    
    func cleanupVideo(for index: Int) {
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