import SwiftUI
import AVKit
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoPlayerView")

struct VideoPlayerView: View {
    let url: URL
    let index: Int
    @ObservedObject var videoManager: VideoManager
    @State private var player: AVPlayer?
    @State private var isLoading = true
    private let videoCacheService = VideoCacheService.shared
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            }
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
        .task {
            do {
                let playerItem = try await videoCacheService.preloadVideo(url: url)
                await MainActor.run {
                    self.player = AVPlayer(playerItem: playerItem)
                    self.isLoading = false
                }
            } catch {
                logger.error("❌ Error loading video: \(error.localizedDescription)")
                // Show error state if needed
            }
        }
    }
}

#if DEBUG
struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView(
            url: URL(string: "https://example.com/video.mp4")!,
            index: 0,
            videoManager: VideoManager()
        )
    }
}
#endif 