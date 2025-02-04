import SwiftUI
import AVKit

@Observable
class VideoManager: ObservableObject {
    private var players: [Int: AVPlayer] = [:]
    
    func player(for index: Int) -> AVPlayer {
        if let player = players[index] {
            return player
        }
        let player = AVPlayer()
        players[index] = player
        return player
    }
    
    func prepareVideo(url: URL, for index: Int) {
        let player = player(for: index)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
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
                player.play()
            }
        }
    }
    
    func cleanupVideo(for index: Int) {
        players[index]?.pause()
        players[index] = nil
    }
} 