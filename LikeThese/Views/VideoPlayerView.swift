import SwiftUI
import AVKit
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoPlayer")

struct VideoPlayerView: View {
    let url: URL
    let index: Int
    @ObservedObject var videoManager: VideoManager
    @State private var isLoading = true
    private let videoCacheService = VideoCacheService.shared
    
    var body: some View {
        ZStack {
            VideoPlayer(player: videoManager.player(for: index))
                .onAppear {
                    logger.debug("📱 VIDEO PLAYER: View appeared for index \(index)")
                    Task {
                        do {
                            let playerItem = try await videoCacheService.preloadVideo(url: url)
                            await MainActor.run {
                                let player = videoManager.player(for: index)
                                if player.currentItem == nil {
                                    player.replaceCurrentItem(with: playerItem)
                                    player.play()
                                    logger.debug("✅ VIDEO PLAYER: Started playback for index \(index)")
                                } else if player.currentItem?.status == .failed {
                                    // Try to recover failed item
                                    player.replaceCurrentItem(with: playerItem)
                                    player.play()
                                    logger.debug("🔄 VIDEO PLAYER: Recovered failed item for index \(index)")
                                } else {
                                    logger.debug("ℹ️ VIDEO PLAYER: Player already has item for index \(index)")
                                }
                                isLoading = false
                            }
                        } catch {
                            logger.error("❌ VIDEO PLAYER: Error loading video \(index): \(error.localizedDescription)")
                            isLoading = false
                        }
                    }
                }
                .onDisappear {
                    logger.debug("📱 VIDEO PLAYER: View disappeared for index \(index)")
                    // Don't cleanup immediately, let VideoManager handle cleanup of distant players
                }
            
            if isLoading || videoManager.bufferingStates[index] == true {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.5)
                        if let progress = videoManager.bufferingProgress[index], !isLoading {
                            Text("\(Int(progress * 100))%")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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