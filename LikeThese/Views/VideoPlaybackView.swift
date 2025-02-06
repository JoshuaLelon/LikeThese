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
    @ObservedObject var videoManager: VideoManager
    @State private var currentIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var isGestureActive = false
    @GestureState private var dragState = false
    @State private var autoAdvanceOffset: CGFloat = 0
    @State private var showError = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var verticalDragOffset: CGFloat = 0
    
    let initialVideo: Video
    let initialIndex: Int
    let videos: [Video]
    
    init(initialVideo: Video, initialIndex: Int, videos: [Video], videoManager: VideoManager) {
        self.initialVideo = initialVideo
        self.initialIndex = initialIndex
        self.videos = videos
        self.videoManager = videoManager
        logger.info("📱 VideoPlaybackView initialized with video: \(initialVideo.id) at index: \(initialIndex), total videos: \(videos.count)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let currentIndex = currentIndex,
                   let video = videos[safe: currentIndex],
                   let url = URL(string: video.url) {
                    VideoPlayerView(
                        url: url,
                        index: currentIndex,
                        videoManager: videoManager
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isGestureActive = true
                                // Determine if drag is more horizontal or vertical
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    // Horizontal drag
                                    horizontalDragOffset = value.translation.width
                                    verticalDragOffset = 0
                                } else {
                                    // Vertical drag
                                    verticalDragOffset = value.translation.height
                                    horizontalDragOffset = 0
                                }
                            }
                            .onEnded { value in
                                handleDragGesture(value, geometry: geometry)
                            }
                    )
                    .offset(x: horizontalDragOffset, y: verticalDragOffset + autoAdvanceOffset)
                }
            }
        }
        .onAppear {
            setupInitialPlayback()
        }
        .onDisappear {
            // Only cleanup if we're not transitioning to another video
            if !videoManager.isTransitioning {
                videoManager.cleanup(context: .dismissal)
            }
        }
        .onChange(of: videoManager.currentState) { newState in
            handleStateChange(newState)
        }
        .alert("Video Error", isPresented: $showError) {
            Button("Go Back") {
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "Failed to load video")
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
                    // Prepare for transition before preloading
                    videoManager.prepareForPlayback(at: initialIndex)
                    
                    try await videoManager.preloadVideo(url: url, forIndex: initialIndex)
                    
                    // Start playing immediately on main thread
                    await MainActor.run {
                        videoManager.startPlaying(at: initialIndex)
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
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showError = true
                        videoManager.cleanup(context: .error)
                    }
                }
            }
        }
    }
    
    private func setupInitialPlayback() {
        currentIndex = initialIndex
        videoManager.startPlaying(at: initialIndex)
    }
    
    private func handleStateChange(_ state: VideoPlayerState) {
        switch state {
        case .playing(let index), .paused(let index):
            currentIndex = index
        case .error(let index, let error):
            currentIndex = index
            errorMessage = error.localizedDescription
            showError = true
        case .loading(let index):
            currentIndex = index
        case .idle:
            break
        }
    }
    
    private func handleDragGesture(_ value: DragGesture.Value, geometry: GeometryProxy) {
        let dragThreshold = geometry.size.height * 0.3
        let horizontalThreshold = geometry.size.width * 0.3
        let velocityX = value.predictedEndLocation.x - value.location.x
        let velocityY = value.predictedEndLocation.y - value.location.y
        
        // Determine if the gesture is primarily horizontal or vertical
        if abs(value.translation.width) > abs(value.translation.height) {
            // Horizontal gesture
            if abs(value.translation.width + velocityX) > horizontalThreshold {
                if value.translation.width > 0 {
                    // Swipe right - return to grid
                    dismiss()
                }
            }
        } else {
            // Vertical gesture
            if abs(value.translation.height + velocityY) > dragThreshold {
                if value.translation.height > 0 {
                    // Swipe down - previous video
                    handleSwipeDown()
                } else {
                    // Swipe up - next video
                    handleSwipeUp()
                }
            }
        }
        
        withAnimation(.spring()) {
            horizontalDragOffset = 0
            verticalDragOffset = 0
            autoAdvanceOffset = 0
            isGestureActive = false
        }
    }
    
    private func handleSwipeDown() {
        guard let current = currentIndex,
              current - 1 >= 0,
              let previousVideo = videos[safe: current - 1],
              let url = URL(string: previousVideo.url) else {
            return
        }
        
        Task {
            do {
                videoManager.prepareForTransition(from: current, to: current - 1)
                try await videoManager.preloadVideo(url: url, forIndex: current - 1)
                videoManager.startPlaying(at: current - 1)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
    }
    
    private func handleSwipeUp() {
        guard let current = currentIndex,
              current + 1 < videos.count,
              let nextVideo = videos[safe: current + 1],
              let url = URL(string: nextVideo.url) else {
            return
        }
        
        Task {
            do {
                videoManager.prepareForTransition(from: current, to: current + 1)
                try await videoManager.preloadVideo(url: url, forIndex: current + 1)
                videoManager.startPlaying(at: current + 1)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
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
}

#if DEBUG
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
            videos: [],
            videoManager: VideoManager.shared
        )
    }
}
#endif 