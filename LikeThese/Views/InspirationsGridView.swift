import SwiftUI
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "InspirationsGrid")

struct InspirationsGridView: View {
    @StateObject private var viewModel = VideoViewModel()
    @State private var selectedVideo: Video?
    @State private var selectedIndex: Int?
    @State private var isVideoPlaybackActive = false
    
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
                    VideoPlaybackView(initialVideo: video, initialIndex: index)
                        .onAppear {
                            logger.debug("🎥 Navigated to video playback for video at index \(index)")
                        }
                }
            }
        }
        .task {
            await viewModel.loadInitialVideos()
        }
    }
    
    private var gridContent: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let itemWidth = availableWidth / 2
            let itemHeight = itemWidth * 16/9
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(viewModel.videos.prefix(4).enumerated()), id: \.element.id) { index, video in
                        gridItem(for: video, index: index, width: itemWidth, height: itemHeight)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private func gridItem(for video: Video, index: Int, width: CGFloat, height: CGFloat) -> some View {
        Button {
            selectedVideo = video
            selectedIndex = index
            isVideoPlaybackActive = true
            logger.debug("👆 User tapped video: \(video.id) at index \(index)")
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
}

#Preview {
    InspirationsGridView()
} 