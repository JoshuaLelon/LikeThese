import SwiftUI
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "InspirationsGrid")

struct InspirationsGridView: View {
    @StateObject private var viewModel = VideoViewModel()
    @StateObject private var videoManager = VideoManager()
    @State private var selectedVideo: Video?
    @State private var selectedIndex: Int?
    @State private var isVideoPlaybackActive = false
    @State private var gridVideos: [Video] = []
    
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
                    VideoPlaybackView(initialVideo: video, initialIndex: index, videos: gridVideos)
                        .onAppear {
                            logger.info("🎥 Navigation - Selected video ID: \(video.id), Index: \(index), Total Videos: \(gridVideos.count)")
                        }
                }
            }
        }
        .task {
            await viewModel.loadInitialVideos()
            // Store the first 4 videos in a stable array
            gridVideos = Array(viewModel.videos.prefix(4))
            logger.info("📱 Grid initialized with \(gridVideos.count) videos")
        }
    }
    
    private var gridContent: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let itemWidth = availableWidth / 2
            let itemHeight = itemWidth * 16/9
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(gridVideos.enumerated()), id: \.element.id) { index, video in
                        gridItem(for: video, index: index, width: itemWidth, height: itemHeight)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private func gridItem(for video: Video, index: Int, width: CGFloat, height: CGFloat) -> some View {
        Button {
            logger.info("👆 Grid selection - Video ID: \(video.id), Index: \(index), Grid Position: \(index % 2),\(index / 2)")
            selectedVideo = video
            selectedIndex = index
            
            // Ensure video is ready for playback
            Task {
                await preloadAndNavigate(to: index)
            }
        } label: {
            if let thumbnailUrl = video.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { phase in
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
                        fallbackVideoImage(video: video, width: width, height: height)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                fallbackVideoImage(video: video, width: width, height: height)
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        .background(Color.black)
        .onAppear {
            logger.info("📱 Grid item appeared - Video ID: \(video.id), Index: \(index)")
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
        guard let video = viewModel.videos[safe: index],
              let url = URL(string: video.url) else {
            logger.error("❌ NAVIGATION: Invalid video URL for index \(index)")
            return
        }
        
        do {
            try await videoManager.preloadVideo(url: url, forIndex: index)
            await MainActor.run {
                selectedVideo = video
                selectedIndex = index
                isVideoPlaybackActive = true
            }
        } catch {
            logger.error("❌ NAVIGATION: Failed to preload video at index \(index): \(error.localizedDescription)")
        }
    }
}

#Preview {
    InspirationsGridView()
} 