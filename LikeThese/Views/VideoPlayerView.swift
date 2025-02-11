import SwiftUI
import AVKit
import FirebaseFirestore

// Import our custom Video model from VideoManager
typealias CustomVideo = LikeThese.Video

struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.presentationMode) var presentationMode
    
    // Add state for fullscreen mode
    @State private var isFullscreen = false
    
    init(video: CustomVideo, boardVideos: [CustomVideo]) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video, boardVideos: boardVideos))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                VideoPlayer(player: viewModel.player)
                    .edgesIgnoringSafeArea(.all)
                
                // Swipe gesture overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                let verticalAmount = value.translation.height
                                let horizontalAmount = value.translation.width
                                
                                // Determine if it's a vertical or horizontal swipe
                                if abs(verticalAmount) > abs(horizontalAmount) {
                                    if verticalAmount < 0 {  // Swipe up
                                        Task {
                                            if isFullscreen {
                                                await viewModel.loadNextSortedVideo()
                                            } else {
                                                await viewModel.loadLeastSimilarVideo()
                                                withAnimation {
                                                    isFullscreen = true
                                                }
                                            }
                                        }
                                    } else {  // Swipe down
                                        withAnimation {
                                            isFullscreen = false
                                            presentationMode.wrappedValue.dismiss()
                                        }
                                    }
                                }
                            }
                    )
                
                // Loading overlay
                if viewModel.isLoading {
                    LoadingView()
                }
                
                // Error overlay
                if let error = viewModel.error {
                    ErrorView(error: error) {
                        Task {
                            await viewModel.retry()
                        }
                    }
                }
            }
            .onChange(of: isFullscreen) { newValue in
                if !newValue {
                    // Reset sorted queue when exiting fullscreen
                    VideoManager.shared.resetSortedQueue()
                }
            }
        }
    }
}

class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var isLoading = false
    @Published var error: Error?
    
    private let video: CustomVideo
    private let boardVideos: [CustomVideo]
    
    init(video: CustomVideo, boardVideos: [CustomVideo]) {
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
    
    private func updatePlayer(with video: CustomVideo) {
        let videoURL = URL(string: video.url)!
        let playerItem = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: playerItem)
        player.play()
    }
}

#Preview {
    VideoPlayerView(
        video: CustomVideo(
            id: "test-video",
            url: "https://example.com/video.mp4",
            thumbnailUrl: "https://example.com/thumbnail.jpg",
            frameUrl: nil
        ),
        boardVideos: []
    )
} 