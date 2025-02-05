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
                            logger.debug("⌛️ LOADING STATE: Initial videos loading")
                        }
                } else if let error = viewModel.error {
                    ErrorView(error: error) {
                        Task {
                            logger.debug("🔄 USER ACTION: Retrying initial video load after error")
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
                                                logger.debug("📱 VIEW LIFECYCLE: Video view \(index) appeared")
                                                logger.debug("📊 QUEUE INFO: Current queue position \(index + 1) of \(viewModel.videos.count)")
                                                if currentIndex == nil {
                                                    currentIndex = index
                                                    logger.debug("🎯 VIEW STATE: Setting initial current index to \(index)")
                                                }
                                            }
                                            .onDisappear {
                                                logger.debug("📱 VIEW LIFECYCLE: Video view \(index) disappeared")
                                            }
                                        
                                        if viewModel.isLoadingMore && index == viewModel.videos.count - 1 {
                                            ProgressView()
                                                .scaleEffect(1.5)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(Color.black.opacity(0.3))
                                                .onAppear {
                                                    logger.debug("⌛️ LOADING STATE: Loading more videos at end of queue")
                                                }
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
                                                logger.debug("👤 USER ACTION: Dragging with offset \(dragOffset)")
                                            }
                                            .onEnded { value in
                                                let height = geometry.size.height
                                                let threshold = height * 0.3 // 30% of screen height
                                                
                                                if abs(value.translation.height) > threshold {
                                                    if value.translation.height < 0 {
                                                        // Swipe up
                                                        if let current = currentIndex,
                                                           current < viewModel.videos.count - 1 {
                                                            logger.debug("👤 USER ACTION: Manual swipe up to next video from index \(current)")
                                                            logger.debug("📊 SWIPE STATS: Swipe distance: \(abs(value.translation.height))px, velocity: \(abs(value.velocity.height))px/s")
                                                            withAnimation {
                                                                currentIndex = current + 1
                                                            }
                                                        }
                                                    } else {
                                                        // Swipe down
                                                        if let current = currentIndex,
                                                           current > 0 {
                                                            logger.debug("👤 USER ACTION: Manual swipe down to previous video from index \(current)")
                                                            logger.debug("📊 SWIPE STATS: Swipe distance: \(abs(value.translation.height))px, velocity: \(abs(value.velocity.height))px/s")
                                                            withAnimation {
                                                                currentIndex = current - 1
                                                            }
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
                                                logger.debug("👤 USER ACTION: Manual play/pause tap on video \(index)")
                                                videoManager.togglePlayPauseAction(index: index)
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
                            logger.debug("🎯 VIEW STATE: Current index changed from \(oldValue ?? -1) to \(index)")
                            logger.debug("📊 QUEUE INFO: \(viewModel.videos.count - (index + 1)) videos remaining in queue")
                            videoManager.pauseAllExcept(index: index)
                            Task {
                                await viewModel.loadMoreVideosIfNeeded(currentIndex: index)
                                // Preload next video if available
                                if index + 1 < viewModel.videos.count,
                                   let nextVideoUrl = URL(string: viewModel.videos[index + 1].url) {
                                    logger.debug("🔄 SYSTEM: Initiating preload for next video (index \(index + 1))")
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
            logger.debug("📱 VIEW LIFECYCLE: VideoPlaybackView appeared")
            logger.debug("📊 INITIAL STATE: \(viewModel.videos.count) videos in initial queue")
            Task {
                await viewModel.loadInitialVideos()
            }
            setupVideoCompletion()
        }
        .onDisappear {
            logger.debug("📱 VIEW LIFECYCLE: VideoPlaybackView disappeared")
        }
    }
    
    func setupVideoCompletion() {
        logger.debug("🔄 SYSTEM: Setting up video completion handler")
        videoManager.onVideoComplete = { [self] index in
            logger.debug("🤖 AUTO ACTION: Video \(index) finished playing")
            logger.debug("📊 QUEUE INFO: Current position \(index + 1) of \(viewModel.videos.count)")
            
            guard !isGestureActive else {
                logger.debug("⚠️ GESTURE STATE: Active gesture detected, cancelling auto-advance")
                return
            }
            
            DispatchQueue.main.async {
                withAnimation {
                    if let current = currentIndex, current == index {
                        let nextIndex = index + 1
                        logger.debug("🤖 AUTO ACTION: Auto-advancing to video \(nextIndex)")
                        if nextIndex < viewModel.videos.count {
                            logger.debug("📊 QUEUE INFO: \(viewModel.videos.count - (nextIndex + 1)) videos remaining after advance")
                        } else {
                            logger.debug("⚠️ QUEUE STATE: Reached end of video queue")
                        }
                        currentIndex = nextIndex
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