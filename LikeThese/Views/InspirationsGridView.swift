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
    @State private var replacingVideoId: String?
    
    // Gesture state tracking
    @State private var isSwipeInProgress = false
    @State private var swipingVideoId: String?
    @State private var swipeOffset: CGFloat = 0
    @State private var removingVideoId: String?
    
    @State private var preloadingIndex: Int?
    
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
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 0) {
                            ForEach(Array(gridVideos.enumerated()), id: \.element.id) { index, video in
                                gridItem(video: video, index: index)
                            }
                        }
                    }
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
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
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
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(gridVideos.enumerated()), id: \.element.id) { index, video in
                gridItem(video: video, index: index)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }
    
    private func gridItem(video: Video, index: Int) -> some View {
        let isReplacing = video.id == viewModel.replacingVideoId
        let isLoading = isReplacing || viewModel.isLoadingVideo(video.id)
        let isBeingDragged = video.id == swipingVideoId
        
        return AsyncImage(url: video.thumbnailUrl.flatMap { URL(string: $0) }) { phase in
            ZStack {
                switch phase {
                case .empty:
                    LoadingView(message: "Loading thumbnail...")
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    LoadingView(message: "Failed to load", isError: true)
                @unknown default:
                    LoadingView(message: "Loading...")
                }
                
                if isLoading {
                    Color.black.opacity(0.7)
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(isReplacing ? "Replacing video..." : "Loading...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                }
            }
            .frame(height: 300)
            .clipped()
            .contentShape(Rectangle())
            .offset(y: isBeingDragged ? swipeOffset : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: swipeOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isSwipeInProgress = true
                        swipingVideoId = video.id
                        swipeOffset = value.translation.height
                    }
                    .onEnded { value in
                        let threshold: CGFloat = -90 // 30% of 300px height
                        if value.translation.height < threshold {
                            Task {
                                await viewModel.removeVideo(video.id)
                            }
                        } else {
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
                    Task {
                        await navigateToVideo(at: index)
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: isLoading)
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
    
    private func navigateToVideo(at index: Int) async {
        guard let video = gridVideos[safe: index],
              let url = URL(string: video.url) else {
            errorMessage = "Invalid video URL"
            showError = true
            return
        }
        
        preloadingIndex = index
        
        do {
            // Prepare for playback
            videoManager.prepareForPlayback(at: index)
            
            // Preload with progress tracking
            try await videoManager.preloadVideo(url: url, forIndex: index)
            
            // Wait for player to be ready with timeout
            try await withTimeout(seconds: 5) {
                while true {
                    if let player = videoManager.player(for: index),
                       player.currentItem?.status == .readyToPlay,
                       player.currentItem?.isPlaybackLikelyToKeepUp == true {
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }
            }
            
            // Navigate when ready
            selectedVideo = video
            selectedIndex = index
            isVideoPlaybackActive = true
            preloadingIndex = nil
        } catch {
            preloadingIndex = nil
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "com.Gauntlet.LikeThese", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

#Preview {
    InspirationsGridView()
} 