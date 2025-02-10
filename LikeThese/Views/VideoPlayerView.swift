import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let url: URL
    let index: Int
    @ObservedObject var videoManager: VideoManager
    @State private var isLoading = true
    @State private var retryCount = 0
    private let maxRetries = 3
    private let videoCacheService = VideoCacheService.shared
    
    var body: some View {
        ZStack {
            VideoPlayer(player: videoManager.player(for: index))
                .aspectRatio(contentMode: .fill)
                .clipped()
                .ignoresSafeArea()
                .onAppear {
                    print("📱 VIDEO PLAYER: View appeared for index \(index)")
                    Task {
                        await loadVideo()
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
    
    private func loadVideo() async {
        repeat {
            do {
                let playerItem = try await videoCacheService.preloadVideo(url: url)
                await MainActor.run {
                    if let player = videoManager.player(for: index) as AVPlayer? {
                        if let currentItem = player.currentItem, currentItem.status == .failed {
                            player.replaceCurrentItem(with: playerItem)
                        }
                        isLoading = false
                        retryCount = 0 // Reset on success
                    }
                }
                break // Success - exit loop
            } catch {
                print("❌ VIDEO PLAYER: Failed to load video at index \(index): \(error.localizedDescription)")
                retryCount += 1
                if retryCount >= maxRetries {
                    print("❌ VIDEO PLAYER: Max retries reached for video at index \(index)")
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000)) // Wait 1 second before retry
            }
        } while retryCount < maxRetries
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