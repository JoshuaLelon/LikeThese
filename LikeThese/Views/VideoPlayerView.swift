import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.presentationMode) var presentationMode
    
    // Add state for fullscreen mode
    @State private var isFullscreen = false
    
    init(video: LikeTheseVideo, boardVideos: [LikeTheseVideo]) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video, boardVideos: boardVideos))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                VideoPlayer(player: viewModel.player)
                    .edgesIgnoringSafeArea(.all)
                
                // Loading indicator
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                // Error alert
                if let error = viewModel.error {
                    VStack {
                        Text("Error playing video")
                            .foregroundColor(.white)
                            .padding()
                        Text(error.localizedDescription)
                            .foregroundColor(.white)
                            .padding()
                        Button("Retry") {
                            Task {
                                await viewModel.retry()
                            }
                        }
                        .padding()
                    }
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                }
            }
        }
    }
}

class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var isLoading = false
    @Published var error: Error?
    
    private let video: LikeTheseVideo
    private let boardVideos: [LikeTheseVideo]
    
    init(video: LikeTheseVideo, boardVideos: [LikeTheseVideo]) {
        self.video = video
        self.boardVideos = boardVideos
        self.player = AVPlayer(url: URL(string: video.url)!)
    }
    
    func loadLeastSimilarVideo() async {
        isLoading = true
        error = nil
        
        do {
            let nextVideo = try await VideoManager.shared.findLeastSimilarVideo(for: boardVideos)
            await MainActor.run {
                updatePlayer(with: nextVideo)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
        }
    }
    
    func loadNextSortedVideo() async {
        isLoading = true
        error = nil
        
        do {
            let nextVideo = try await VideoManager.shared.getNextSortedVideo(currentBoardVideos: boardVideos)
            await MainActor.run {
                updatePlayer(with: nextVideo)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
        }
    }
    
    func retry() async {
        await loadLeastSimilarVideo()
    }
    
    private func updatePlayer(with video: LikeTheseVideo) {
        let videoURL = URL(string: video.url)!
        let playerItem = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: playerItem)
        player.play()
    }
}

#Preview {
    VideoPlayerView(
        video: LikeTheseVideo(
            id: "test-video",
            url: "https://example.com/video.mp4",
            thumbnailUrl: "https://example.com/thumbnail.jpg",
            frameUrl: nil,
            timestamp: Timestamp(date: Date())
        ),
        boardVideos: []
    )
} 