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
    @State private var isInitialLoad = true
    
    init() {
        logger.debug("📱 VideoPlaybackView initialized")
    }
    
    var body: some View {
        GeometryReader { geometry in
            mainContent(geometry)
        }
        .ignoresSafeArea(edges: .all)
        .statusBar(hidden: true)
        .onAppear {
            logger.debug("📱 VIEW LIFECYCLE: VideoPlaybackView appeared")
            logger.debug("📊 INITIAL STATE: \(viewModel.videos.count) videos in initial queue")
            Task {
                await viewModel.loadInitialVideos()
                if isInitialLoad {
                    // Set initial index only on first load
                    currentIndex = 0
                    isInitialLoad = false
                    logger.debug("🎯 VIEW STATE: Setting initial index to 0 on first load")
                }
            }
            setupVideoCompletion()
        }
        .onDisappear {
            logger.debug("📱 VIEW LIFECYCLE: VideoPlaybackView disappeared")
            // Don't reset isInitialLoad here to maintain state across login/logout
        }
    }
    
    @ViewBuilder
    private func mainContent(_ geometry: GeometryProxy) -> some View {
        ZStack {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else {
                videoScrollView(geometry)
            }
        }
        .ignoresSafeArea()
    }
    
    private var loadingView: some View {
        ProgressView("Loading videos...")
            .onAppear {
                logger.debug("⌛️ LOADING STATE: Initial videos loading")
            }
    }
    
    private func errorView(_ error: Error) -> some View {
        ErrorView(error: error) {
            Task {
                logger.debug("🔄 USER ACTION: Retrying initial video load after error")
                await viewModel.loadInitialVideos()
            }
        }
    }
    
    private func videoScrollView(_ geometry: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                videoList(geometry)
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentIndex)
        .simultaneousGesture(
            DragGesture()
                .onChanged { _ in }
        )
        .onChange(of: currentIndex) { oldValue, newValue in
            handleIndexChange(oldValue: oldValue, newValue: newValue)
        }
    }
    
    @ViewBuilder
    private func videoList(_ geometry: GeometryProxy) -> some View {
        ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
            if let url = URL(string: video.url) {
                videoCell(url: url, index: index, geometry: geometry)
            }
        }
    }
    
    private func videoCell(url: URL, index: Int, geometry: GeometryProxy) -> some View {
        ZStack {
            VideoPlayerView(url: url, index: index, videoManager: videoManager)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .id(index)
                .onAppear {
                    handleVideoAppear(index)
                }
                .onDisappear {
                    logger.debug("📱 VIEW LIFECYCLE: Video view \(index) disappeared")
                }
            
            if viewModel.isLoadingMore && index == viewModel.videos.count - 1 {
                loadingMoreView
            }
        }
        .gesture(createDragGesture(geometry))
        .highPriorityGesture(createTapGesture(index))
    }
    
    private var loadingMoreView: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.3))
            .onAppear {
                logger.debug("⌛️ LOADING STATE: Loading more videos at end of queue")
            }
    }
    
    private func handleVideoAppear(_ index: Int) {
        logger.debug("📱 VIEW LIFECYCLE: Video view \(index) appeared")
        logger.debug("📊 QUEUE INFO: Current queue position \(index + 1) of \(viewModel.videos.count)")
        
        // Only set currentIndex if it's nil and we're not in initial load
        if currentIndex == nil && !isInitialLoad {
            currentIndex = index
            logger.debug("🎯 VIEW STATE: Setting current index to \(index)")
        }
        
        // Ensure video is ready to play
        Task {
            if let url = URL(string: viewModel.videos[index].url) {
                await videoManager.preloadVideo(url: url, forIndex: index)
            }
        }
    }
    
    private func handleIndexChange(oldValue: Int?, newValue: Int?) {
        if let index = newValue {
            logger.debug("🎯 VIEW STATE: Current index changed from \(oldValue ?? -1) to \(index)")
            logger.debug("📊 QUEUE INFO: \(viewModel.videos.count - (index + 1)) videos remaining in queue")
            
            // Cleanup old video if it exists
            if let oldIndex = oldValue {
                videoManager.cleanupVideo(for: oldIndex)
            }
            
            // Pause all except current
            videoManager.pauseAllExcept(index: index)
            
            Task {
                await handleVideoPreload(index)
            }
        }
    }
    
    private func handleVideoPreload(_ index: Int) async {
        // Load more videos if needed
        await viewModel.loadMoreVideosIfNeeded(currentIndex: index)
        
        // Preload next video if available
        if index + 1 < viewModel.videos.count,
           let nextVideoUrl = URL(string: viewModel.videos[index + 1].url) {
            logger.debug("🔄 SYSTEM: Initiating preload for next video (index \(index + 1))")
            await videoManager.preloadVideo(url: nextVideoUrl, forIndex: index + 1)
        }
        
        // Cleanup videos that are too far away (more than 2 positions)
        let distantPlayers = videoManager.getDistantPlayers(from: index)
        for playerIndex in distantPlayers {
            logger.debug("🧹 CLEANUP: Removing distant video at index \(playerIndex)")
            videoManager.cleanupVideo(for: playerIndex)
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
    
    private func createDragGesture(_ geometry: GeometryProxy) -> some Gesture {
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
    }
    
    private func createTapGesture(_ index: Int) -> some Gesture {
        TapGesture()
            .onEnded {
                logger.debug("👤 USER ACTION: Manual play/pause tap on video \(index)")
                videoManager.togglePlayPauseAction(index: index)
            }
    }
}

struct VideoPlaybackView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlaybackView()
    }
} 