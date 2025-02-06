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
    @State private var autoAdvanceOffset: CGFloat = 0
    
    let initialVideo: Video
    let initialIndex: Int
    let videos: [Video]
    
    init(initialVideo: Video, initialIndex: Int, videos: [Video]) {
        self.initialVideo = initialVideo
        self.initialIndex = initialIndex
        self.videos = videos
        logger.info("📱 VideoPlaybackView initialized with video: \(initialVideo.id) at index: \(initialIndex), total videos: \(videos.count)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            mainContent(geometry)
        }
        .task {
            // Initialize state and preload immediately
            viewModel.videos = videos
            currentIndex = initialIndex
            logger.info("📊 INITIAL STATE: Setting up \(viewModel.videos.count) videos, current index: \(initialIndex)")
            
            // Setup video completion handler first
            setupVideoCompletion()
            
            // Start playing the current video immediately
            if let url = URL(string: initialVideo.url) {
                logger.info("🎬 Starting playback for initial video: \(initialVideo.id)")
                
                // Ensure player is ready before starting playback
                do {
                    try await videoManager.preloadVideo(url: url, forIndex: initialIndex)
                    
                    // Start playing immediately on main thread
                    await MainActor.run {
                        videoManager.togglePlayPauseAction(index: initialIndex)
                        logger.info("▶️ Playback started for initial video at index: \(initialIndex)")
                    }
                    
                    // Preload the next video if available
                    if initialIndex + 1 < videos.count,
                       let nextVideoUrl = URL(string: videos[initialIndex + 1].url) {
                        try await videoManager.preloadVideo(url: nextVideoUrl, forIndex: initialIndex + 1)
                        logger.info("🔄 Preloaded next video at index: \(initialIndex + 1)")
                    }
                } catch {
                    logger.error("❌ Failed to preload initial video: \(error.localizedDescription)")
                }
            }
        }
        .onDisappear {
            // Only cleanup if we're actually leaving the view hierarchy
            logger.info("📱 VIEW LIFECYCLE: VideoPlaybackView disappeared - cleaning up resources")
            if let currentIdx = currentIndex {
                videoManager.pauseAllExcept(index: currentIdx)
                // Prepare for transition to grid view (using -1 as grid view index)
                videoManager.prepareForTransition(from: currentIdx, to: -1)
                // Finish transition immediately as we're leaving
                videoManager.finishTransition(at: -1)
            }
        }
        .ignoresSafeArea(edges: .all)
        .statusBar(hidden: true)
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
                logger.info("⌛️ LOADING STATE: Initial videos loading")
            }
    }
    
    private func errorView(_ error: Error) -> some View {
        ErrorView(error: error) {
            Task {
                logger.info("🔄 USER ACTION: Retrying initial video load after error")
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
                .offset(y: index == currentIndex ? autoAdvanceOffset : 0)
                .onAppear {
                    handleVideoAppear(index)
                }
        }
        .gesture(createDragGesture(geometry))
        .highPriorityGesture(createTapGesture(index))
    }
    
    private func handleVideoAppear(_ index: Int) {
        logger.info("📱 Video view \(index) appeared")
        logger.info("📊 Current queue position \(index + 1) of \(viewModel.videos.count)")
        
        // Ensure video is ready to play
        Task {
            if let url = URL(string: viewModel.videos[index].url) {
                do {
                    try await videoManager.preloadVideo(url: url, forIndex: index)
                    logger.info("🔄 Preloaded video at index: \(index)")
                } catch {
                    logger.error("❌ Failed to preload video at index \(index): \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleIndexChange(oldValue: Int?, newValue: Int?) {
        if let index = newValue {
            logger.info("🎯 Current index changed from \(oldValue ?? -1) to \(index)")
            logger.info("📊 \(viewModel.videos.count - (index + 1)) videos remaining in queue")
            
            // Prepare for transition if we have an old index
            if let oldIndex = oldValue {
                videoManager.prepareForTransition(from: oldIndex, to: index)
            }
            
            // Pause all except current
            videoManager.pauseAllExcept(index: index)
            
            Task {
                await handleVideoPreload(index)
                // Finish transition after preloading
                videoManager.finishTransition(at: index)
            }
        }
    }
    
    private func handleVideoPreload(_ index: Int) async {
        // Load more videos if needed
        await viewModel.loadMoreVideosIfNeeded(currentIndex: index)
        
        // Preload next video if available
        if index + 1 < viewModel.videos.count,
           let nextVideoUrl = URL(string: viewModel.videos[index + 1].url) {
            logger.info("🔄 SYSTEM: Initiating preload for next video (index \(index + 1))")
            do {
                try await videoManager.preloadVideo(url: nextVideoUrl, forIndex: index + 1)
            } catch {
                logger.error("❌ Failed to preload next video at index \(index + 1): \(error.localizedDescription)")
            }
        }
        
        // No need to manually cleanup distant videos anymore as it's handled by the transition system
    }
    
    func setupVideoCompletion() {
        logger.info("🔄 SYSTEM: Setting up video completion handler")
        videoManager.onVideoComplete = { [self] index in
            logger.info("🎬 VIDEO COMPLETION HANDLER: Auto-advance triggered for completed video at index \(index)")
            logger.info("📊 QUEUE POSITION: Video \(index + 1) of \(viewModel.videos.count) in queue")
            
            guard !isGestureActive else {
                logger.info("⚠️ AUTO-ADVANCE CANCELLED: Active gesture detected during video completion at index \(index)")
                return
            }
            
            // Ensure we're on the main thread for UI updates
            Task { @MainActor in
                if let current = currentIndex, current == index {
                    let nextIndex = index + 1
                    if nextIndex < viewModel.videos.count {
                        // Prepare for transition
                        videoManager.prepareForTransition(from: index, to: nextIndex)
                        
                        // First animate the swipe up
                        withAnimation(.easeInOut(duration: 0.3)) {
                            autoAdvanceOffset = -UIScreen.main.bounds.height * 0.3
                            logger.info("🔄 AUTO-ADVANCE ANIMATION: Started swipe-up animation for completed video \(index)")
                        }
                        
                        // Wait for animation to complete
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        
                        // After the swipe up animation, advance to next video
                        withAnimation {
                            logger.info("🎯 AUTO-ADVANCE TRANSITION: Moving from completed video \(index) to next video \(nextIndex)")
                            logger.info("📊 QUEUE STATUS: \(viewModel.videos.count - (nextIndex + 1)) videos remaining after auto-advance")
                            currentIndex = nextIndex
                            // Reset the offset for the next video
                            autoAdvanceOffset = 0
                        }
                        
                        // Finish transition after animation
                        videoManager.finishTransition(at: nextIndex)
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
                logger.info("🖐️ Drag gesture active")
            }
            .onChanged { value in
                dragOffset = value.translation.height
                logger.info("👤 USER ACTION: Dragging with offset \(dragOffset)")
            }
            .onEnded { value in
                let height = geometry.size.height
                let threshold = height * 0.3 // 30% of screen height
                
                if abs(value.translation.height) > threshold {
                    if value.translation.height < 0 {
                        // Swipe up
                        if let current = currentIndex,
                           current < viewModel.videos.count - 1 {
                            logger.info("👤 USER ACTION: Manual swipe up to next video from index \(current)")
                            logger.info("📊 SWIPE STATS: Swipe distance: \(abs(value.translation.height))px, velocity: \(abs(value.velocity.height))px/s")
                            withAnimation {
                                currentIndex = current + 1
                            }
                        }
                    } else {
                        // Swipe down
                        if let current = currentIndex,
                           current > 0 {
                            logger.info("👤 USER ACTION: Manual swipe down to previous video from index \(current)")
                            logger.info("📊 SWIPE STATS: Swipe distance: \(abs(value.translation.height))px, velocity: \(abs(value.velocity.height))px/s")
                            withAnimation {
                                currentIndex = current - 1
                            }
                        }
                    }
                }
                
                dragOffset = 0
                isGestureActive = false
                logger.info("🖐️ Drag gesture ended")
            }
    }
    
    private func createTapGesture(_ index: Int) -> some Gesture {
        TapGesture()
            .onEnded {
                logger.info("👤 USER ACTION: Manual play/pause tap on video \(index)")
                videoManager.togglePlayPauseAction(index: index)
            }
    }
}

struct VideoPlaybackView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlaybackView(
            initialVideo: Video(
                id: "1",
                url: "https://example.com/video1.mp4",
                thumbnailUrl: nil,
                timestamp: Timestamp(date: Date())
            ),
            initialIndex: 0,
            videos: []
        )
    }
} 