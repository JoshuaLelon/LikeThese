import SwiftUI
import AVKit
import FirebaseFirestore

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
    
    let initialVideo: LikeTheseVideo
    let initialIndex: Int
    let videos: [LikeTheseVideo]
    
    init(initialVideo: LikeTheseVideo, initialIndex: Int, videos: [LikeTheseVideo], videoManager: VideoManager, viewModel: VideoViewModel) {
        self.initialVideo = initialVideo
        self.initialIndex = initialIndex
        self.videos = videos
        self.videoManager = videoManager
        self.viewModel = viewModel
        print("📱 VideoPlaybackView initialized with video: \(initialVideo.id) at index: \(initialIndex), total videos: \(videos.count)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Current video stays fixed in place
                if let currentIndex = currentIndex,
                   let video = videos[safe: currentIndex],
                   let url = URL(string: video.url) {
                    VideoPlayer(player: videoManager.player(for: currentIndex))
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
                    VideoPlayer(player: videoManager.player(for: toIndex))
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
        .onChange(of: videoManager.currentState) { oldState, newState in
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
            print("📊 INITIAL STATE: Setting up \(viewModel.videos.count) videos, current index: \(initialIndex)")
            
            // Setup video completion handler first
            setupVideoCompletion()
            
            // Start playing the current video immediately
            if let url = URL(string: initialVideo.url) {
                print("🎬 Starting playback for initial video: \(initialVideo.id)")
                
                // Ensure player is ready before starting playback
                do {
                    // Prepare for transition before preloading
                    videoManager.prepareForPlayback(at: initialIndex)
                    
                    try await videoManager.preloadVideo(url: url, forIndex: initialIndex)
                    
                    // Start playing immediately on main thread
                    await MainActor.run {
                        videoManager.startPlaying(at: initialIndex)
                        print("▶️ Playback started for initial video at index: \(initialIndex)")
                    }
                    
                    // Preload the next video if available
                    if initialIndex + 1 < videos.count,
                       let nextVideoUrl = URL(string: videos[initialIndex + 1].url) {
                        try await videoManager.preloadVideo(url: nextVideoUrl, forIndex: initialIndex + 1)
                        print("🔄 Preloaded next video at index: \(initialIndex + 1)")
                    }
                } catch {
                    print("❌ Failed to preload initial video: \(error.localizedDescription)")
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
        let dragThreshold = geometry.size.height * 0.2
        let horizontalThreshold = geometry.size.width * 0.3
        let velocityX = value.predictedEndLocation.x - value.location.x
        let velocityY = value.predictedEndLocation.y - value.location.y
        let distanceThreshold: CGFloat = UIScreen.main.bounds.height * 0.3
        let velocityMultiplier: CGFloat = 0.3
        
        // Reset offsets if gesture doesn't meet threshold
        let resetOffsets = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
              current - 1 >= 0 else {
            return
        }
        
        Task {
            do {
                // Begin gesture transition with immediate effect
                videoManager.beginTransition(.gesture(from: current, to: current - 1)) {
                    Task { @MainActor in
                        // Set initial state for animation
                        transitionState = .transitioning(from: current, to: current - 1)
                        transitionOpacity = 0  // Start with new video invisible
                        incomingOffset = -UIScreen.main.bounds.height  // Position above
                    }
                }
                
                // Try to get previous video from sequence
                if let previousVideo = viewModel.getPreviousVideo(from: current),
                   let url = URL(string: previousVideo.url) {
                    // Ensure previous video is preloaded and ready
                    try await videoManager.preloadVideo(url: url, forIndex: current - 1)
                    
                    // Prepare next video but don't start playing yet
                    if let player = videoManager.player(for: current - 1) {
                        await player.seek(to: .zero)
                    }
                    
                    // Animate old video down while bringing new video in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        offset = UIScreen.main.bounds.height  // Move current video down
                        incomingOffset = 0  // Bring new video to center
                        transitionOpacity = 1  // Fade in new video
                    }
                    
                    // Wait for animation to complete
                    try await Task.sleep(nanoseconds: 300_000_000)
                    
                    // Start playing new video only after animation
                    if let player = videoManager.player(for: current - 1) {
                        player.playImmediately(atRate: 1.0)
                        videoManager.startPlaying(at: current - 1)
                    }
                    
                    // Capture videoManager before MainActor.run
                    let manager = videoManager
                    await MainActor.run {
                        currentIndex = current - 1
                        transitionState = .none
                        offset = 0  // Reset offset for next interaction
                        manager.finishTransition(at: current - 1)
                    }
                }
            } catch {
                print("❌ Failed to handle swipe down: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
    }
    
    private func handleSwipeUp() {
        guard let current = currentIndex else { return }
        
        Task {
            do {
                // Begin gesture transition with immediate effect
                videoManager.beginTransition(.gesture(from: current, to: current + 1)) {
                    Task { @MainActor in
                        // Set initial state for animation
                        transitionState = .transitioning(from: current, to: current + 1)
                        transitionOpacity = 0  // Start with new video invisible
                        incomingOffset = UIScreen.main.bounds.height  // Position below
                    }
                }
                
                // Try to get next video and preload upcoming videos
                if let nextVideo = viewModel.getNextVideo(from: current),
                   let url = URL(string: nextVideo.url) {
                    // Ensure next video is preloaded and ready
                    try await videoManager.preloadVideo(url: url, forIndex: current + 1)
                    
                    // Prepare next video but don't start playing yet
                    if let player = videoManager.player(for: current + 1) {
                        await player.seek(to: .zero)
                    }
                    
                    // Animate old video up while bringing new video in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        offset = -UIScreen.main.bounds.height  // Move current video up
                        incomingOffset = 0  // Bring new video to center
                        transitionOpacity = 1  // Fade in new video
                    }
                    
                    // Wait for animation to complete
                    try await Task.sleep(nanoseconds: 300_000_000)
                    
                    // Start playing new video only after animation
                    if let player = videoManager.player(for: current + 1) {
                        player.playImmediately(atRate: 1.0)
                        videoManager.startPlaying(at: current + 1)
                    }
                    
                    // Capture videoManager before MainActor.run
                    let manager = videoManager
                    await MainActor.run {
                        currentIndex = current + 1
                        transitionState = .none
                        offset = 0  // Reset offset for next interaction
                        manager.finishTransition(at: current + 1)
                    }
                    
                    // Preload next 12 videos in background
                    Task {
                        // Preload in batches of 3 to avoid overwhelming the system
                        for batchStart in stride(from: 2, to: 13, by: 3) {
                            for offset in batchStart...(min(batchStart + 2, 12)) {
                                if let futureVideo = viewModel.getNextVideo(from: current + offset - 1),
                                   let futureUrl = URL(string: futureVideo.url) {
                                    try? await videoManager.preloadVideo(url: futureUrl, forIndex: current + offset)
                                }
                            }
                            // Small delay between batches
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                    }
                }
            } catch {
                print("❌ Failed to handle swipe up: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
    }
    
    func setupVideoCompletion() {
        print("🔄 SYSTEM: Setting up video completion handler")
        videoManager.onVideoComplete = { [self] index in
            print("🎬 VIDEO COMPLETION HANDLER: Auto-advance triggered for completed video at index \(index)")
            print("📊 QUEUE POSITION: Video \(index + 1) of \(viewModel.videos.count) in queue")
            
            // Only cancel auto-advance if there's an active drag gesture
            guard isGestureActive && dragState else {
                print("✅ AUTO-ADVANCE: Proceeding with auto-advance for video \(index)")
                return
            }
            
            print("⚠️ AUTO-ADVANCE CANCELLED: Active gesture detected during video completion at index \(index)")
        }
    }
}

#Preview {
    VideoPlaybackView(
        initialVideo: LikeTheseVideo(
            id: "test-video",
            url: "https://example.com/video.mp4",
            thumbnailUrl: "https://example.com/thumbnail.jpg",
            frameUrl: nil,
            timestamp: Timestamp(date: Date())
        ),
        initialIndex: 0,
        videos: [],
        videoManager: VideoManager.shared,
        viewModel: VideoViewModel()
    )
} 