import SwiftUI
import AVKit
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoPlayback")

struct VideoPlaybackView: View {
    @StateObject private var viewModel = VideoViewModel()
    @StateObject private var videoManager = VideoManager()
    @State private var currentIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @GestureState private var dragState = false
    
    init() {
        logger.debug("📱 VideoPlaybackView initialized")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    ProgressView("Loading videos...")
                        .onAppear {
                            logger.debug("⌛️ Showing loading indicator")
                        }
                } else if let error = viewModel.error {
                    ErrorView(error: error) {
                        Task {
                            await viewModel.loadInitialVideos()
                        }
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                                if let url = URL(string: video.url) {
                                    ZStack {
                                        VideoPlayerView(url: url, index: index, videoManager: videoManager)
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .id(index)
                                        
                                        if viewModel.isLoadingMore && index == viewModel.videos.count - 1 {
                                            ProgressView()
                                                .scaleEffect(1.5)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(Color.black.opacity(0.3))
                                        }
                                    }
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                dragOffset = value.translation.height
                                            }
                                            .onEnded { value in
                                                let threshold = geometry.size.height * 0.3
                                                if abs(value.translation.height) > threshold {
                                                    withAnimation {
                                                        if value.translation.height < 0 {
                                                            // Swipe up
                                                            currentIndex = (currentIndex ?? 0) + 1
                                                            Task {
                                                                await viewModel.loadMoreVideosIfNeeded(currentIndex: currentIndex ?? 0)
                                                            }
                                                        } else {
                                                            // Swipe down
                                                            currentIndex = max(0, (currentIndex ?? 0) - 1)
                                                        }
                                                    }
                                                }
                                                dragOffset = 0
                                            }
                                    )
                                    .highPriorityGesture(
                                        TapGesture()
                                            .onEnded {
                                                videoManager.togglePlayPause(index: index)
                                            }
                                    )
                                }
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentIndex)
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { _ in }
                    )
                    .onChange(of: currentIndex) { oldValue, newValue in
                        if let index = newValue {
                            videoManager.pauseAllExcept(index: index)
                            Task {
                                await viewModel.loadMoreVideosIfNeeded(currentIndex: index)
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(edges: .all)
        .statusBar(hidden: true)
        .onAppear {
            logger.debug("🎬 VideoPlaybackView appeared, loading initial videos")
            Task {
                await viewModel.loadInitialVideos()
            }
        }
    }
}

struct VideoPlaybackView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlaybackView()
    }
} 