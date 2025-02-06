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
    @ObservedObject var viewModel: VideoViewModel
    @ObservedObject var videoManager: VideoManager
    @State private var currentIndex: Int?
    @State private var isGestureActive = false
    @GestureState private var dragState = false
    @State private var showError = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var transitionState: TransitionState = .none
    @State private var transitionOpacity: Double = 1
    @State private var incomingOffset: CGFloat = 0
    
    private enum TransitionState {
        case none
        case transitioning(from: Int, to: Int)
    }
    
    let initialVideo: Video
    let initialIndex: Int
    let videos: [Video]
    
    init(initialVideo: Video, initialIndex: Int, videos: [Video], videoManager: VideoManager, viewModel: VideoViewModel) {
        self.initialVideo = initialVideo
        self.initialIndex = initialIndex
        self.videos = videos
        self.videoManager = videoManager
        self.viewModel = viewModel
        logger.info("📱 VideoPlaybackView initialized with video: \(initialVideo.id) at index: \(initialIndex), total videos: \(videos.count)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Current video stays fixed in place
                if let currentIndex = currentIndex,
                   let video = videos[safe: currentIndex],
                   let url = URL(string: video.url) {
                    VideoPlayerView(
                        url: url,
                        index: currentIndex,
                        videoManager: videoManager
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isGestureActive = true
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    horizontalOffset = value.translation.width
                                    offset = 0
                                } else {
                                    offset = value.translation.height
                                    horizontalOffset = 0
                                }
                            }
                            .onEnded { value in
                                handleDragGesture(value, geometry: geometry)
                            }
                    )
                }
                
                // Only the incoming video moves in or out
                if case .transitioning(_, let toIndex) = transitionState,
                   let video = videos[safe: toIndex],
                   let url = URL(string: video.url) {
                    VideoPlayerView(
                        url: url,
                        index: toIndex,
                        videoManager: videoManager
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()
                    .offset(y: incomingOffset)
                    .opacity(1 - transitionOpacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
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
            // Only handle state changes when not in a transition
            if case .none = transitionState {
                handleStateChange(newState)
            }
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
        
        // Reset offsets if gesture doesn't meet threshold
        let resetOffsets = {
            withAnimation(.spring()) {
                horizontalOffset = 0
                offset = 0
                isGestureActive = false
            }
        }
        
        // Determine if the gesture is primarily horizontal or vertical
        if abs(value.translation.width) > abs(value.translation.height) {
            // Horizontal gesture
            if abs(value.translation.width + velocityX) > horizontalThreshold {
                if value.translation.width > 0 {
                    // Swipe right - return to grid
                    withAnimation(.easeInOut(duration: 0.3)) {
                        horizontalOffset = geometry.size.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                } else {
                    resetOffsets()
                }
            } else {
                resetOffsets()
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
            } else {
                resetOffsets()
            }
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
                // Begin gesture transition
                videoManager.beginTransition(.gesture(from: current, to: current - 1)) {
                    // Set transition state and position incoming video
                    Task { @MainActor in
                        transitionState = .transitioning(from: current, to: current - 1)
                        transitionOpacity = 1
                        incomingOffset = -UIScreen.main.bounds.height
                    }
                }

                // Ensure previous video is preloaded and ready
                try await videoManager.preloadVideo(url: url, forIndex: current - 1)
                
                // Ensure player is ready and start playing
                if let player = videoManager.player(for: current - 1) {
                    // Seek to start and prepare for playback
                    await player.seek(to: .zero)
                    player.playImmediately(atRate: 1.0)
                    
                    // Start playing before animation
                    videoManager.startPlaying(at: current - 1)
                    logger.info("▶️ SWIPE DOWN: Started playing video at index \(current - 1)")
                }

                // Animate the transition
                withAnimation(.easeInOut(duration: 0.3)) {
                    incomingOffset = 0
                    transitionOpacity = 0
                }

                // Wait for animation to complete
                try await Task.sleep(nanoseconds: 300_000_000)

                // Update state
                await MainActor.run {
                    currentIndex = current - 1
                    transitionState = .none
                    transitionOpacity = 1
                }

                // End transition in VideoManager
                videoManager.endTransition()

                // Preload the previous video if available
                if let prevPrevVideo = videos[safe: current - 2],
                   let prevUrl = URL(string: prevPrevVideo.url) {
                    try await videoManager.preloadVideo(url: prevUrl, forIndex: current - 2)
                }
            } catch {
                logger.error("❌ Failed to handle swipe down: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
    }
    
    private func handleSwipeUp() {
        guard let current = currentIndex,
              current + 1 < videos.count else {
            return
        }

        Task {
            // Load more videos if needed
            await viewModel.loadMoreVideosIfNeeded(currentIndex: current)

            // Now handle the swipe up
            if let nextVideo = videos[safe: current + 1],
               let url = URL(string: nextVideo.url) {
                do {
                    // Begin gesture transition
                    videoManager.beginTransition(.gesture(from: current, to: current + 1)) {
                        // Set transition state and position incoming video
                        Task { @MainActor in
                            transitionState = .transitioning(from: current, to: current + 1)
                            transitionOpacity = 1
                            incomingOffset = UIScreen.main.bounds.height
                        }
                    }

                    // Preload and prepare the next video
                    try await videoManager.preloadVideo(url: url, forIndex: current + 1)
                    
                    // Ensure player is ready and start playing
                    if let player = videoManager.player(for: current + 1) {
                        // Seek to start and prepare for playback
                        await player.seek(to: .zero)
                        player.playImmediately(atRate: 1.0)
                        
                        // Start playing before animation
                        videoManager.startPlaying(at: current + 1)
                        logger.info("▶️ SWIPE UP: Started playing video at index \(current + 1)")
                    }

                    // Animate the transition
                    withAnimation(.easeInOut(duration: 0.3)) {
                        incomingOffset = 0
                        transitionOpacity = 0
                    }

                    // Wait for animation to complete
                    try await Task.sleep(nanoseconds: 300_000_000)

                    // Update state
                    await MainActor.run {
                        currentIndex = current + 1
                        transitionState = .none
                        transitionOpacity = 1
                    }

                    // End transition in VideoManager
                    videoManager.endTransition()

                    // Preload the next video if available
                    if let nextNextVideo = videos[safe: current + 2],
                       let nextUrl = URL(string: nextNextVideo.url) {
                        try await videoManager.preloadVideo(url: nextUrl, forIndex: current + 2)
                    }
                } catch {
                    logger.error("❌ Failed to handle swipe up: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    showError = true
                    videoManager.cleanup(context: .error)
                }
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
            
            Task { @MainActor in
                if let current = currentIndex, current == index {
                    let nextIndex = index + 1
                    if nextIndex < viewModel.videos.count {
                        // Set transition state and position incoming video
                        transitionState = .transitioning(from: index, to: nextIndex)
                        transitionOpacity = 1
                        incomingOffset = UIScreen.main.bounds.height
                        
                        // Prepare for transition
                        videoManager.prepareForTransition(from: index, to: nextIndex)
                        
                        // Animate the incoming video into position
                        withAnimation(.easeInOut(duration: 0.35)) {
                            incomingOffset = 0
                            transitionOpacity = 0
                            logger.info("🔄 AUTO-ADVANCE ANIMATION: Started transition animation")
                        }
                        
                        // Wait for animation
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        
                        // Complete transition
                        if currentIndex == index {
                            currentIndex = nextIndex
                            transitionState = .none
                            transitionOpacity = 1
                            
                            logger.info("✅ AUTO-ADVANCE: Completed transition to video \(nextIndex)")
                            videoManager.finishTransition(at: nextIndex)
                        }
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
            videoManager: VideoManager.shared,
            viewModel: VideoViewModel()
        )
    }
}
#endif 