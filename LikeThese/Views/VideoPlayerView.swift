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
                .aspectRatio(contentMode: .fill)
                .clipped()
                .ignoresSafeArea()
                .onAppear {
                    logger.debug("📱 VIDEO PLAYER: View appeared for index \(index)")
                    Task {
                        do {
                            let playerItem = try await videoCacheService.preloadVideo(url: url)
                            await MainActor.run {
                                if let player = videoManager.player(for: index) as AVPlayer? {
                                    if let currentItem = player.currentItem {
                                        if currentItem.status == .failed {
                                            player.replaceCurrentItem(with: playerItem)
                                            player.play()
                                            logger.debug("✅ VIDEO PLAYER: Recovered failed playback for index \(index)")
                                        } else {
                                            logger.debug("ℹ️ VIDEO PLAYER: Player already has working item for index \(index)")
                                        }
                                    } else {
                                        player.replaceCurrentItem(with: playerItem)
                                        player.play()
                                        logger.debug("✅ VIDEO PLAYER: Started new playback for index \(index)")
                                    }
                                } else {
                                    logger.error("❌ VIDEO PLAYER: No player available for index \(index)")
                                }
                                isLoading = false
                            }
                        } catch {
                            logger.error("❌ VIDEO PLAYER: Error loading video \(index): \(error.localizedDescription)")
                            isLoading = false
                        }
                    }
                }
            
            if isLoading || videoManager.bufferingStates[index] == true {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
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
        }
    }
}

#if DEBUG
struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView(
            url: URL(string: "https://example.com/video.mp4")!,
            index: 0,
            videoManager: VideoManager.shared
        )
    }
}
#endif 