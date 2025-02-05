import Foundation
import AVKit
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoManager")

class VideoManager: ObservableObject {
    private var players: [Int: AVPlayer] = [:]
    
    func player(for index: Int) -> AVPlayer {
        if let existingPlayer = players[index] {
            return existingPlayer
        }
        
        let player = AVPlayer()
        players[index] = player
        return player
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
            }
        }
    }
    
    func cleanupVideo(for index: Int) {
        players[index]?.pause()
        players[index] = nil
    }
} 