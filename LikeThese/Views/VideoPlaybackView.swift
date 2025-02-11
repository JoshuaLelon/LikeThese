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
    @State private var isFullscreen = false
    @State private var isNavigatingToVideo = false
    @State private var currentVideos: [LikeTheseVideo]
    
    private enum TransitionState {
        case none
        case transitioning(from: Int, to: Int)
    }
    
    let initialVideo: LikeTheseVideo
    let initialIndex: Int
    
    init(initialVideo: LikeTheseVideo, initialIndex: Int, videos: [LikeTheseVideo], videoManager: VideoManager, viewModel: VideoViewModel) {
        self.initialVideo = initialVideo
        self.initialIndex = initialIndex
        self._currentVideos = State(initialValue: videos)
        self.videoManager = videoManager
        self.viewModel = viewModel
        print("📱 Init: video \(initialVideo.id) at \(initialIndex)/\(videos.count)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Current video stays fixed in place
                if let currentIndex = currentIndex,
                   let video = currentVideos[safe: currentIndex],
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
                   let video = currentVideos[safe: toIndex],
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
            viewModel.videos = currentVideos
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
                    if initialIndex + 1 < currentVideos.count,
                       let nextVideoUrl = URL(string: currentVideos[initialIndex + 1].url) {
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
                        isFullscreen = false  // Exit fullscreen when returning to grid
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
                videoManager.beginTransition(.gesture(from: current, to: current - 1)) {
                    Task { @MainActor in
                        transitionState = .transitioning(from: current, to: current - 1)
                        transitionOpacity = 0
                        incomingOffset = -UIScreen.main.bounds.height
                    }
                }
                
                if let previousVideo = viewModel.getPreviousVideo(from: current),
                   let url = URL(string: previousVideo.url) {
                    try await videoManager.preloadVideo(url: url, forIndex: current - 1)
                    
                    if let player = videoManager.player(for: current - 1) {
                        await player.seek(to: .zero)
                    }
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        offset = UIScreen.main.bounds.height
                        incomingOffset = 0
                        transitionOpacity = 1
                    }
                    
                    try await Task.sleep(nanoseconds: 300_000_000)
                    
                    if let player = videoManager.player(for: current - 1) {
                        player.playImmediately(atRate: 1.0)
                        videoManager.startPlaying(at: current - 1)
                    }
                    
                    let manager = videoManager
                    await MainActor.run {
                        currentIndex = current - 1
                        transitionState = .none
                        offset = 0
                        manager.finishTransition(at: current - 1)
                    }
                }
            } catch {
                print("❌ Swipe down failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
    }
    
    private func handleSwipeUp() {
        guard let current = currentIndex else { return }
        
        print("👆 SWIPE: Starting swipe up from index \(current)")
        print("🎥 MODE: Currently in \(isFullscreen ? "fullscreen" : "grid") mode")
        
        Task {
            do {
                await MainActor.run {
                    transitionState = .transitioning(from: current, to: current + 1)
                    transitionOpacity = 0
                    incomingOffset = UIScreen.main.bounds.height
                }
                
                var nextVideo: LikeTheseVideo?
                if isFullscreen {
                    print("🎥 FULLSCREEN: Handling swipe in fullscreen mode")
                    do {
                        // Load the current video and board videos into the ViewModel if not already loaded
                        if viewModel.currentVideo == nil {
                            print("🔄 FULLSCREEN: Loading initial video state")
                            viewModel.loadVideo(currentVideos[current], boardVideos: currentVideos)
                            print("📊 FULLSCREEN: Loaded video \(currentVideos[current].id) with \(currentVideos.count) board videos")
                        }
                        
                        print("🎬 FULLSCREEN: Fetching next video from sorted queue")
                        nextVideo = try await viewModel.getNextSortedVideo()
                        print("✅ FULLSCREEN: Got next video: \(nextVideo?.id ?? "nil")")
                    } catch {
                        print("❌ QUEUE: Queue ended: \(error.localizedDescription)")
                        // Instead of dismissing, try to get a fresh queue
                        do {
                            print("🔄 QUEUE: Queue ended, fetching fresh queue...")
                            let currentBoardVideos = currentVideos
                            print("📊 QUEUE: Creating new queue with \(currentBoardVideos.count) board videos")
                            try await viewModel.createSortedQueue(from: currentVideos[current], boardVideos: currentBoardVideos)
                            nextVideo = try await viewModel.getNextSortedVideo()
                            print("✅ QUEUE: Successfully refreshed queue and got next video: \(nextVideo?.id ?? "nil")")
                        } catch {
                            print("❌ QUEUE: Failed to refresh queue: \(error.localizedDescription)")
                            print("🔄 QUEUE: Current state before dismissal:")
                            viewModel.debugQueueState()
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isFullscreen = false
                                }
                                dismiss()
                            }
                            return
                        }
                    }
                } else {
                    print("📱 GRID: Getting next video in grid mode")
                    nextVideo = viewModel.getNextVideo(from: current)
                    print("✅ GRID: Got next video: \(nextVideo?.id ?? "nil")")
                    
                    if nextVideo == nil {
                        print("🔄 GRID: No next video, attempting to enter fullscreen mode")
                        isFullscreen = true
                        viewModel.loadVideo(currentVideos[current], boardVideos: currentVideos)
                        print("📊 GRID: Loaded video \(currentVideos[current].id) with \(currentVideos.count) board videos")
                        do {
                            try await viewModel.createSortedQueue(from: currentVideos[current], boardVideos: currentVideos)
                            nextVideo = try await viewModel.getNextSortedVideo()
                            print("✅ GRID->FULLSCREEN: Successfully got next video: \(nextVideo?.id ?? "nil")")
                        } catch {
                            print("❌ GRID->FULLSCREEN: Failed to get next video: \(error.localizedDescription)")
                        }
                    }
                }
                
                if let nextVideo = nextVideo,
                   let url = URL(string: nextVideo.url) {
                    print("🔄 SWIPE: Loading next video at index \(current + 1)")
                    try await videoManager.preloadVideo(url: url, forIndex: current + 1)
                    
                    if let player = videoManager.player(for: current + 1) {
                        await player.seek(to: .zero)
                    }
                    
                    await MainActor.run {
                        if current + 1 >= currentVideos.count {
                            print("📥 SWIPE: Appending new video to list")
                            currentVideos.append(nextVideo)
                        }
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = -UIScreen.main.bounds.height
                            incomingOffset = 0
                            transitionOpacity = 1
                        }
                    }
                    
                    try? await Task.sleep(nanoseconds: UInt64(0.3 * Double(NSEC_PER_SEC)))
                    await MainActor.run {
                        currentIndex = current + 1
                        transitionState = .none
                        offset = 0
                        videoManager.finishTransition(at: current + 1)
                        print("✅ SWIPE: Successfully transitioned to video at index \(current + 1)")
                    }
                } else {
                    print("❌ SWIPE: No next video available")
                }
            } catch {
                print("❌ Swipe up failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                videoManager.cleanup(context: .error)
            }
        }
    }
    
    func setupVideoCompletion() {
        print("🔄 Setting up completion handler")
        videoManager.onVideoComplete = { [self] index in
            print("🎬 Video \(index + 1)/\(viewModel.videos.count) completed")
            
            guard isGestureActive && dragState else {
                print("✅ Auto-advancing to next video")
                return
            }
            
            print("⚠️ Auto-advance cancelled: gesture active")
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }
            
            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "VideoPlaybackView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            // Return the first completed result (either the operation or timeout)
            let result = try await group.next()
            
            // Cancel any remaining tasks
            group.cancelAll()
            
            return try result ?? {
                throw NSError(domain: "VideoPlaybackView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation failed"])
            }()
        }
    }
    
    private func navigateToVideo(at index: Int) async {
        guard let video = currentVideos[safe: index],
              let url = URL(string: video.url) else {
            errorMessage = "Invalid video URL"
            showError = true
            return
        }
        
        do {
            isNavigatingToVideo = true
            isFullscreen = true  // Set fullscreen mode when navigating to video
            
            // Preserve state before navigation
            viewModel.preserveCurrentState()
            print("🔄 NAVIGATION: Preserved grid state before video playback")
            
            // Prepare for playback
            videoManager.prepareForPlayback(at: index)
            
            // Preload with progress tracking
            try await videoManager.preloadVideo(url: url, forIndex: index)
            
            // Wait for player to be ready with timeout
            try await withTimeout(seconds: 5) {
                while true {
                    if let player = videoManager.player(for: index),
                       player.currentItem?.status == .readyToPlay,
                       player.currentItem?.isPlaybackLikelyToKeepUp == true {
                        break
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second
                }
            }
            
            print("🎥 NAVIGATION: Successfully navigated to video at index \(index)")
        } catch {
            print("❌ Navigation failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
            isNavigatingToVideo = false
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