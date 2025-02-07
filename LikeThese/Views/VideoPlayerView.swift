import SwiftUI
import AVKit
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoPlayer")

struct VideoPlayerView: View {
    let url: URL
    let index: Int
    @ObservedObject var videoManager: VideoManager
    @State private var isLoading = true
    @State private var loadError: Error?
    private let videoCacheService = VideoCacheService.shared
    
    var body: some View {
        ZStack {
            if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.yellow)
                    Text("Failed to load video")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                }
                .padding()
            } else {
                VideoPlayer(player: videoManager.player(for: index))
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .ignoresSafeArea()
                    .onAppear {
                        logger.debug("📱 VIDEO PLAYER: View appeared for index \(index)")
                        Task {
                            do {
                                let playerItem = try await videoCacheService.preloadVideo(url: url)
                                
                                // Verify player readiness
                                try await withTimeout(seconds: 5.0) {
                                    while true {
                                        if let player = videoManager.player(for: index),
                                           let currentItem = player.currentItem,
                                           currentItem.status == .readyToPlay,
                                           currentItem.isPlaybackLikelyToKeepUp {
                                            return
                                        }
                                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                                    }
                                }
                                
                                await MainActor.run {
                                    guard let player = videoManager.player(for: index) else {
                                        logger.error("❌ VIDEO PLAYER: No player available for index \(index)")
                                        isLoading = false
                                        loadError = VideoPlayerError.noPlayer
                                        return
                                    }
                                    
                                    player.replaceCurrentItem(with: playerItem)
                                    player.play()
                                    logger.debug("✅ VIDEO PLAYER: Started playback for index \(index)")
                                    isLoading = false
                                }
                            } catch {
                                logger.error("❌ VIDEO PLAYER: Error loading video \(index): \(error.localizedDescription)")
                                await MainActor.run {
                                    loadError = error
                                    isLoading = false
                                }
                            }
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
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw VideoPlayerError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

enum VideoPlayerError: Error {
    case timeout
    case noPlayer
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