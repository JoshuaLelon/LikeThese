import SwiftUI
import FirebaseFirestore

struct InspirationsGridView: View {
    @StateObject private var viewModel = VideoViewModel()
    @ObservedObject var videoManager: VideoManager
    @State private var selectedVideo: LikeTheseVideo?
    @State private var selectedIndex: Int?
    @State private var isVideoPlaybackActive = false
    @State private var gridVideos: [LikeTheseVideo] = []
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var replacingVideoId: String?
    
    // Gesture state tracking
    @State private var isSwipeInProgress = false
    @State private var swipingVideoId: String?
    @State private var swipeOffset: CGFloat = 0
    @State private var removingVideoId: String?
    
    @State private var preloadingIndex: Int?
    
    // Add new properties for layout
    @State private var gridSpacing: CGFloat = 36 // Wider gap between videos (was 28)
    @State private var gridPadding: CGFloat = 1 // Minimal padding around grid edges
    
    // Add new properties for touch targets
    @State private var touchTargetSize: CGFloat = 44 // Standard iOS touch target size
    @State private var isSwipingGap = false
    @State private var swipingGapLocation: GapLocation?
    
    // Add new properties for multi-swipe
    @State private var swipingVideos: Set<String> = []
    @State private var multiSwipeOffset: CGFloat = 0
    private let twoVideoSwipeThreshold: CGFloat = 0.35 // 35% threshold
    private let fourVideoSwipeThreshold: CGFloat = 0.40 // 40% threshold
    
    // Add new properties for video replacement
    @State private var loadingSlots: Set<Int> = []
    @State private var preloadingThumbnails: Set<Int> = []
    
    // Add new properties for visual feedback
    @State private var swipeOpacity: CGFloat = 1.0
    @State private var multiSwipeOpacity: CGFloat = 1.0
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Navigation state
    @State private var isNavigatingToVideo = false
    @State private var isReturningFromVideo = false
    
    private enum GapLocation: Equatable {
        case horizontal(Int) // Index of left video
        case vertical(Int)   // Index of top video
        case center         // Center point where all four videos meet
    }
    
    @MainActor
    init(videoManager: VideoManager = VideoManager.shared) {
        self.videoManager = videoManager
    }
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    
    private func calculateVideoHeight(for width: CGFloat) -> CGFloat {
        // Calculate height maintaining 9:16 aspect ratio
        // Account for spacing and padding
        let availableWidth = (width - gridPadding * 2 - gridSpacing) / 2
        let height = availableWidth * (16/9)
        print("📐 GRID: Calculated video height \(height) for width \(width)")
        return height
    }
    
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
                    VideoPlaybackView(
                        initialVideo: video,
                        initialIndex: index,
                        videos: viewModel.videos,
                        videoManager: videoManager,
                        viewModel: viewModel
                    )
                    .onAppear {
                        print("🎥 Navigation - Selected video ID: \(video.id), Index: \(index), Total Videos: \(viewModel.videos.count)")
                    }
                    .onDisappear {
                        isReturningFromVideo = true
                        print("🔄 NAVIGATION: Returning from video playback")
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .task {
            await viewModel.loadInitialVideos()
            gridVideos = viewModel.videos
            print("📱 Grid initialized with \(gridVideos.count) videos")
        }
        .onChange(of: viewModel.videos) { newVideos in
            withAnimation(.spring()) {
                gridVideos = newVideos
                print("🔄 Grid updated with \(gridVideos.count) videos")
            }
        }
        .onAppear {
            if isReturningFromVideo {
                // Restore state when returning from video playback
                viewModel.restorePreservedState()
                isReturningFromVideo = false
                print("🔄 NAVIGATION: Restored grid state after video playback")
            }
        }
    }
    
    private var gridContent: some View {
        GeometryReader { geometry in
            let videoHeight = calculateVideoHeight(for: geometry.size.width)
            ScrollView {
                ZStack {
                    // Videos Grid
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: gridSpacing),
                            GridItem(.flexible(), spacing: gridSpacing)
                        ],
                        spacing: gridSpacing
                    ) {
                        ForEach(Array(gridVideos.enumerated()), id: \.element.id) { index, video in
                            gridItem(video: video, index: index)
                                .frame(height: videoHeight)
                        }
                    }
                    .padding(gridPadding)
                    
                    // Add refresh button in center
                    Button(action: {
                        Task {
                            await viewModel.loadInitialVideos()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.8))
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .shadow(radius: 10)
                    }
                    .position(x: geometry.size.width / 2, y: videoHeight + gridSpacing / 2)
                    
                    // Touch Target Areas
                    if gridVideos.count >= 4 {
                        // Vertical gap between left videos
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: touchTargetSize, height: videoHeight * 2 + gridSpacing)
                            .position(x: geometry.size.width / 4, y: videoHeight + gridSpacing / 2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        handleGapDragChange(value, at: .vertical(0))
                                    }
                                    .onEnded { value in
                                        handleGapDragEnd(value)
                                    }
                            )
                        
                        // Vertical gap between right videos
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: touchTargetSize, height: videoHeight * 2 + gridSpacing)
                            .position(x: geometry.size.width * 3/4, y: videoHeight + gridSpacing / 2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        handleGapDragChange(value, at: .vertical(1))
                                    }
                                    .onEnded { value in
                                        handleGapDragEnd(value)
                                    }
                            )
                        
                        // Horizontal gap between top videos
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: geometry.size.width, height: touchTargetSize)
                            .position(x: geometry.size.width / 2, y: videoHeight / 2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        handleGapDragChange(value, at: .horizontal(0))
                                    }
                                    .onEnded { value in
                                        handleGapDragEnd(value)
                                    }
                            )
                        
                        // Horizontal gap between bottom videos
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: geometry.size.width, height: touchTargetSize)
                            .position(x: geometry.size.width / 2, y: videoHeight * 1.5 + gridSpacing)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        handleGapDragChange(value, at: .horizontal(2))
                                    }
                                    .onEnded { value in
                                        handleGapDragEnd(value)
                                    }
                            )
                        
                        // Center intersection point
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: touchTargetSize, height: touchTargetSize)
                            .position(x: geometry.size.width / 2, y: videoHeight + gridSpacing / 2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        handleGapDragChange(value, at: .center)
                                    }
                                    .onEnded { value in
                                        handleGapDragEnd(value)
                                    }
                            )
                    }
                }
            }
        }
    }
    
    private func gridItem(video: LikeTheseVideo, index: Int) -> some View {
        let isReplacing = video.id == viewModel.replacingVideoId
        let isLoading = isReplacing || viewModel.isLoadingVideo(video.id) || loadingSlots.contains(index)
        let isPreloadingThumbnail = preloadingThumbnails.contains(index)
        let isBeingDragged = video.id == swipingVideoId
        let isPartOfMultiSwipe = swipingVideos.contains(video.id)
        
        if isLoading {
            print("⏳ GRID ITEM: Loading state for video \(video.id) at index \(index)")
        }
        if isPreloadingThumbnail {
            print("🔄 GRID ITEM: Preloading thumbnail for video \(video.id) at index \(index)")
        }
        
        return AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
            ZStack {
                switch phase {
                case .empty:
                    LoadingView(message: isPreloadingThumbnail ? "Preloading..." : "Loading thumbnail...")
                    .onAppear {
                        print("⏳ THUMBNAIL: Started loading for video \(video.id)")
                    }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(9/16, contentMode: .fill)
                        .onAppear {
                            print("✅ THUMBNAIL: Successfully loaded for video \(video.id)")
                        }
                case .failure:
                    LoadingView(message: "Failed to load", isError: true)
                        .onAppear {
                            print("❌ THUMBNAIL: Failed to load for video \(video.id)")
                            Task {
                                do {
                                    // Try up to 3 times with exponential backoff
                                    for attempt in 0..<3 {
                                        do {
                                            print("🔄 Attempt \(attempt + 1) to refresh thumbnail for video \(video.id)")
                                            
                                            // First try to refresh all URLs
                                            try await FirestoreService.shared.refreshVideoUrls()
                                            
                                            // Add exponential backoff delay
                                            let delay = Double(pow(2, Double(attempt)))
                                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                            
                                            // Then handle the specific thumbnail failure
                                            try await FirestoreService.shared.handleThumbnailLoadFailure(for: video.id)
                                            
                                            // Add a small delay before updating the UI
                                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                            
                                            // Get the updated video with fresh URLs
                                            if let index = gridVideos.firstIndex(where: { $0.id == video.id }) {
                                                let updatedVideo = try await FirestoreService.shared.getUpdatedVideo(for: video.id)
                                                
                                                // Update on main thread
                                                await MainActor.run {
                                                    gridVideos[index] = updatedVideo
                                                }
                                                
                                                // If successful, break the retry loop
                                                print("✅ Successfully refreshed thumbnail for video \(video.id) on attempt \(attempt + 1)")
                                                return
                                            }
                                        } catch {
                                            print("❌ Attempt \(attempt + 1) failed for video \(video.id): \(error.localizedDescription)")
                                            if attempt == 2 {
                                                throw error // Re-throw on last attempt
                                            }
                                        }
                                    }
                                } catch {
                                    print("❌ All attempts failed to handle thumbnail load failure for video \(video.id): \(error.localizedDescription)")
                                }
                            }
                        }
                @unknown default:
                    LoadingView(message: "Loading...")
                }
                
                if isLoading {
                    Color.black.opacity(0.7)
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(isReplacing ? "Replacing video..." : 
                             (isPreloadingThumbnail ? "Preloading..." : "Loading..."))
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .opacity(isPartOfMultiSwipe ? multiSwipeOpacity : (isBeingDragged ? swipeOpacity : 1.0))
            .offset(y: isBeingDragged ? swipeOffset : (isPartOfMultiSwipe ? multiSwipeOffset : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBeingDragged ? swipeOffset : multiSwipeOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isSwipingGap && !isLoading {
                            isSwipeInProgress = true
                            swipingVideoId = video.id
                            swipeOffset = value.translation.height
                            print("🔄 SWIPE: Single video swipe in progress - Video: \(video.id), Offset: \(value.translation.height)")
                            
                            // Update opacity based on swipe progress
                            withAnimation(.easeInOut(duration: 0.1)) {
                                swipeOpacity = calculateOpacity(for: value.translation.height, threshold: 0.3)
                            }
                        }
                    }
                    .onEnded { value in
                        if !isSwipingGap && !isLoading {
                            let threshold: CGFloat = -90 // 30% of 300px height
                            if value.translation.height < threshold {
                                print("🗑️ SWIPE: Removing single video \(video.id) after successful swipe")
                                triggerHapticFeedback()
                                
                                Task {
                                    loadingSlots.insert(index)
                                    print("⏳ LOADING: Started loading state for index \(index)")
                                    await viewModel.removeVideo(video.id)
                                    print("✅ REMOVAL: Completed removal of video \(video.id)")
                                    loadingSlots.remove(index)
                                    print("✨ CLEANUP: Cleared loading state for index \(index)")
                                }
                            } else {
                                print("↩️ SWIPE: Cancelled swipe for video \(video.id)")
                                withAnimation(.spring()) {
                                    swipeOffset = 0
                                    swipeOpacity = 1.0
                                }
                            }
                            isSwipeInProgress = false
                            swipingVideoId = nil
                        }
                    }
            )
            .onTapGesture {
                if !isSwipeInProgress && !isSwipingGap && !isLoading {
                    Task {
                        await navigateToVideo(at: index)
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: isLoading)
    }
    
    private func fallbackVideoImage(video: LikeTheseVideo, width: CGFloat, height: CGFloat) -> some View {
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
    
    private func navigateToVideo(at index: Int) async {
        guard let video = gridVideos[safe: index],
              let url = URL(string: video.url) else {
            errorMessage = "Invalid video URL"
            showError = true
            return
        }
        
        do {
            isNavigatingToVideo = true
            
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
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }
            }
            
            // Navigate when ready
            selectedVideo = video
            selectedIndex = index
            isVideoPlaybackActive = true
            isNavigatingToVideo = false
            print("🎥 NAVIGATION: Successfully navigated to video at index \(index)")
        } catch {
            isNavigatingToVideo = false
            errorMessage = error.localizedDescription
            showError = true
            print("❌ NAVIGATION: Failed to navigate to video at index \(index): \(error.localizedDescription)")
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "com.Gauntlet.LikeThese", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func calculateOpacity(for translation: CGFloat, threshold: CGFloat) -> CGFloat {
        let progress = min(abs(translation) / (threshold * UIScreen.main.bounds.height), 1.0)
        let opacity = 1.0 - (progress * 0.5)
        print("🎨 OPACITY: Calculated opacity \(opacity) for translation \(translation)")
        return opacity
    }
    
    private func triggerHapticFeedback() {
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
        print("📳 HAPTIC: Triggered feedback")
    }
    
    private func handleGapDragChange(_ value: DragGesture.Value, at location: GapLocation) {
        isSwipingGap = true
        swipingGapLocation = location
        multiSwipeOffset = value.translation.height
        
        // Log swipe progress
        let locationDesc = switch location {
            case .horizontal(let index): "horizontal gap at index \(index)"
            case .vertical(let index): "vertical gap at index \(index)"
            case .center: "center gap"
        }
        print("🔄 SWIPE: Multi-swipe in progress - Location: \(locationDesc), Offset: \(value.translation.height)")
        
        // Update opacity based on swipe progress
        let threshold = location == .center ? fourVideoSwipeThreshold : twoVideoSwipeThreshold
        withAnimation(.easeInOut(duration: 0.1)) {
            multiSwipeOpacity = calculateOpacity(for: value.translation.height, threshold: threshold)
        }
        
        // Determine affected videos based on gap location
        switch location {
        case .horizontal(let index):
            // For horizontal gaps, affect videos on both sides
            if index < gridVideos.count {
                swipingVideos = [gridVideos[index].id]
                if index + 1 < gridVideos.count {
                    swipingVideos.insert(gridVideos[index + 1].id)
                }
                print("👆 SWIPE: Affecting horizontal videos at indices \(index) and \(index + 1)")
            }
        case .vertical(let index):
            // For vertical gaps, affect videos above and below
            if index < gridVideos.count {
                swipingVideos = [gridVideos[index].id]
                if index + 2 < gridVideos.count {
                    swipingVideos.insert(gridVideos[index + 2].id)
                }
                print("👆 SWIPE: Affecting vertical videos at indices \(index) and \(index + 2)")
            }
        case .center:
            // For center point, affect all four videos
            swipingVideos = Set(gridVideos.prefix(4).map { $0.id })
            print("👆 SWIPE: Affecting all four videos in grid")
        }
    }
    
    private func handleGapDragEnd(_ value: DragGesture.Value) {
        let threshold = swipingGapLocation == .center ? 
            fourVideoSwipeThreshold : twoVideoSwipeThreshold
        let swipeDistance = abs(value.translation.height)
        let screenHeight = UIScreen.main.bounds.height
        let swipePercentage = swipeDistance / screenHeight
        
        print("🔄 SWIPE: Multi-swipe ended - Distance: \(swipeDistance), Percentage: \(swipePercentage * 100)%")
        
        if swipePercentage >= threshold && value.translation.height < 0 {
            // Trigger haptic feedback
            triggerHapticFeedback()
            print("📳 FEEDBACK: Triggered haptic for successful multi-swipe")
            
            // Remove affected videos simultaneously
            Task {
                // Convert to array to maintain order
                let videoIds = Array(swipingVideos)
                
                // Animate videos upward and fade out
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    multiSwipeOffset = -UIScreen.main.bounds.height
                    multiSwipeOpacity = 0
                }
                
                // Wait for animation to complete
                try? await Task.sleep(nanoseconds: UInt64(0.3 * Double(NSEC_PER_SEC)))
                
                // Remove and replace videos atomically
                await viewModel.removeMultipleVideos(videoIds)
                
                // Reset state with animation
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    multiSwipeOffset = 0
                    multiSwipeOpacity = 1
                }
            }
        } else {
            // Reset state with animation if threshold not met
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                multiSwipeOffset = 0
                multiSwipeOpacity = 1
            }
        }
        
        // Reset state
        isSwipingGap = false
        swipingGapLocation = nil
        swipingVideos.removeAll()
        print("🔄 RESET: Cleared multi-swipe state")
    }
}

#Preview {
    InspirationsGridView()
} 