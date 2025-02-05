import SwiftUI
import AVKit
import os
import FirebaseFirestore

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoPlayback")

// Add safe subscript for arrays
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct VideoPlaybackView: View {
    @StateObject private var viewModel = VideoViewModel()
    @StateObject private var videoManager = VideoManager()
    @State private var currentIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var isGestureActive = false
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
                                            .onAppear {
                                                logger.debug("📺 Video view appeared for index \(index)")
                                                if currentIndex == nil {
                                                    currentIndex = index
                                                    logger.debug("📺 Setting initial current index to \(index)")
                                                }
                                            }
                                        
                                        if viewModel.isLoadingMore && index == viewModel.videos.count - 1 {
                                            ProgressView()
                                                .scaleEffect(1.5)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(Color.black.opacity(0.3))
                                        }
                                    }
                                    .gesture(
                                        DragGesture()
                                            .updating($dragState) { _, state, _ in
                                                state = true
                                                isGestureActive = true
                                                logger.debug("🖐️ Drag gesture active")
                                            }
                                            .onChanged { value in
                                                dragOffset = value.translation.height
                                                logger.debug("🖐️ Drag offset: \(dragOffset)")
                                            }
                                            .onEnded { value in
                                                let threshold = geometry.size.height * 0.3
                                                if abs(value.translation.height) > threshold {
                                                    withAnimation {
                                                        if value.translation.height < 0 {
                                                            // Swipe up
                                                            logger.debug("⬆️ Swiping up from index \(currentIndex ?? -1)")
                                                            currentIndex = (currentIndex ?? 0) + 1
                                                            Task {
                                                                await viewModel.loadMoreVideosIfNeeded(currentIndex: currentIndex ?? 0)
                                                            }
                                                        } else {
                                                            // Swipe down
                                                            logger.debug("⬇️ Swiping down from index \(currentIndex ?? -1)")
                                                            currentIndex = max(0, (currentIndex ?? 0) - 1)
                                                        }
                                                    }
                                                }
                                                dragOffset = 0
                                                isGestureActive = false
                                                logger.debug("🖐️ Drag gesture ended")
                                            }
                                    )
                                    .highPriorityGesture(
                                        TapGesture()
                                            .onEnded {
                                                logger.debug("👆 Tap gesture on index \(index)")
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
                            logger.debug("📺 Current index changed from \(oldValue ?? -1) to \(index)")
                            videoManager.pauseAllExcept(index: index)
                            Task {
                                await viewModel.loadMoreVideosIfNeeded(currentIndex: index)
                                // Preload next video if available
                                if index + 1 < viewModel.videos.count,
                                   let nextVideoUrl = URL(string: viewModel.videos[index + 1].url) {
                                    await videoManager.preloadVideo(url: nextVideoUrl, forIndex: index + 1)
                                }
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
            setupVideoCompletion()
        }
    }
    
    func setupVideoCompletion() {
        logger.debug("🔄 Setting up video completion handler")
        videoManager.onVideoComplete = { [self] index in
            logger.debug("📺 Video at index \(index) completed")
            
            // Only handle completion if we're not in the middle of a gesture
            guard !isGestureActive else {
                logger.debug("🖐️ Gesture active, ignoring video completion")
                return
            }
            
            // Simply increment the index on the main thread
            DispatchQueue.main.async {
                withAnimation {
                    if let current = currentIndex, current == index {
                        logger.debug("⏭️ Auto-advancing to next video from index \(index)")
                        currentIndex = index + 1
                    }
                }
            }
        }
    }
}

struct VideoPlaybackView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlaybackView()
    }
} 