import SwiftUI
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "InspirationsGrid")

struct InspirationsGridView: View {
    @StateObject private var viewModel = VideoViewModel()
    @ObservedObject var videoManager: VideoManager
    @State private var selectedVideo: Video?
    @State private var selectedIndex: Int?
    @State private var isVideoPlaybackActive = false
    @State private var gridVideos: [Video] = []
    @State private var showError = false
    @State private var errorMessage: String?
    
    // Gesture state tracking
    @State private var isSwipeInProgress = false
    @State private var swipingVideoId: String?
    @State private var swipeOffset: CGFloat = 0
    @State private var removingVideoId: String?
    
    @MainActor
    init(videoManager: VideoManager = VideoManager.shared) {
        self.videoManager = videoManager
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading {
                    LoadingView(message: "Loading your inspirations...")
                } else if let error = viewModel.error {
                    ErrorView(error: error) {
                        Task {
                            await viewModel.loadInitialVideos()
                        }
                    }
                } else {
                    gridContent
                }
            }
            .navigationDestination(isPresented: $isVideoPlaybackActive) {
                if let video = selectedVideo,
                   let index = selectedIndex {
                    VideoPlaybackView(
                        initialVideo: video,
                        initialIndex: index,
                        videos: viewModel.videos,
                        videoManager: videoManager,
                        viewModel: viewModel
                    )
                    .onAppear {
                        logger.info("🎥 Navigation - Selected video ID: \(video.id), Index: \(index), Total Videos: \(viewModel.videos.count)")
                    }
                }
            }
        }
        .task {
            await viewModel.loadInitialVideos()
            gridVideos = viewModel.videos
            logger.info("📱 Grid initialized with \(gridVideos.count) videos")
        }
        .onChange(of: viewModel.videos) { newVideos in
            withAnimation(.spring()) {
                gridVideos = newVideos
                logger.info("🔄 Grid updated with \(gridVideos.count) videos")
            }
        }
    }
    
    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(gridVideos.enumerated()), id: \.element.id) { index, video in
                    gridItem(video: video, index: index)
                }
            }
        }
    }
    
    private func gridItem(video: Video, index: Int) -> some View {
        let isRemoving = video.id == removingVideoId
        let isBeingDragged = video.id == swipingVideoId
        
        return AsyncImage(url: video.thumbnailUrl.flatMap { URL(string: $0) }) { phase in
            Group {
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 300)
            .clipped()
            .opacity(isRemoving ? 0 : 1)
            .offset(y: isBeingDragged ? swipeOffset : 0)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        isSwipeInProgress = true
                        swipingVideoId = video.id
                        swipeOffset = value.translation.height
                        logger.info("🔄 Swipe in progress - Video ID: \(video.id), Offset: \(swipeOffset)")
                    }
                    .onEnded { value in
                        let threshold: CGFloat = -90 // 30% of 300px height
                        if value.translation.height < threshold {
                            logger.info("🗑️ Removing video with upward swipe - Video ID: \(video.id)")
                            withAnimation(.spring()) {
                                removingVideoId = video.id
                            }
                            Task {
                                await viewModel.removeVideo(video.id)
                            }
                        } else {
                            logger.info("↩️ Cancelling swipe - Video ID: \(video.id)")
                            withAnimation(.spring()) {
                                swipeOffset = 0
                            }
                        }
                        isSwipeInProgress = false
                        swipingVideoId = nil
                    }
            )
            .onTapGesture {
                if !isSwipeInProgress {
                    logger.info("👆 Grid selection - Video ID: \(video.id), Index: \(index), Grid Position: \(index/2),\(index%2)")
                    Task {
                        await preloadAndNavigate(to: index)
                    }
                }
            }
        }
    }
    
    private func fallbackVideoImage(video: Video, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let videoUrl = URL(string: video.url) {
                AsyncImage(url: videoUrl) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.black
                            ProgressView()
                                .tint(.white)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    case .failure:
                        ZStack {
                            Color.black
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ZStack {
                    Color.black
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    func preloadAndNavigate(to index: Int) async {
        guard let video = gridVideos[safe: index],
              let url = URL(string: video.url) else {
            logger.error("❌ NAVIGATION: Invalid video URL for index \(index)")
            await MainActor.run {
                errorMessage = "Invalid video URL"
                showError = true
                videoManager.cleanup(context: .error)
            }
            return
        }
        
        do {
            // Prepare for transition before preloading
            videoManager.prepareForPlayback(at: index)
            
            // Preload video and wait for completion
            try await videoManager.preloadVideo(url: url, forIndex: index)
            
            // Only navigate if preload was successful and we haven't started another preload
            await MainActor.run {
                if videoManager.currentState.currentIndex == index {
                    selectedVideo = video
                    selectedIndex = index
                    isVideoPlaybackActive = true
                    logger.info("✅ NAVIGATION: Successfully preloaded and navigating to video at index \(index)")
                } else {
                    logger.info("⚠️ NAVIGATION: Preload completed but state changed, cancelling navigation to index \(index)")
                }
            }
        } catch {
            logger.error("❌ NAVIGATION: Failed to preload video at index \(index): \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
    }
}

#Preview {
    InspirationsGridView()
} 