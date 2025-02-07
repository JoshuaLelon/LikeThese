import SwiftUI
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "InspirationsGrid")

extension UIImpactFeedbackGenerator {
    /// A safe wrapper around impactOccurred() that handles the throws requirement.
    /// 
    /// According to Apple's documentation and implementation, impactOccurred() is marked
    /// as throws but never actually throws in practice. This wrapper method safely handles
    /// the throws requirement without unnecessary error handling overhead.
    /// 
    /// Note: This is a workaround for a SwiftLint false positive that flags the throws
    /// requirement even though the method never throws in practice.
    func safeImpactOccurred() {
        // This method never actually throws in practice, so we can safely use try?
        try? self.impactOccurred()
    }
}

struct InspirationsGridView: View {
    @StateObject private var viewModel = VideoViewModel()
    @ObservedObject var videoManager: VideoManager
    @State private var selectedVideo: Video?
    @State private var selectedIndex: Int?
    @State private var isVideoPlaybackActive = false
    @State private var gridVideos: [Video] = []
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
    
    private enum GapLocation: Equatable {
        case horizontal(Int) // Index of left video
        case vertical(Int)   // Index of top video
        case center         // Center point where all four videos meet
    }
    
    @MainActor
    init(videoManager: VideoManager = .shared) {
        self.videoManager = videoManager
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    
    private func calculateVideoHeight(for width: CGFloat) -> CGFloat {
        // Calculate height maintaining 9:16 aspect ratio
        // Account for spacing and padding
        let availableWidth = (width - gridPadding * 2 - gridSpacing) / 2
        let height = availableWidth * (16/9)
        logger.debug("📐 GRID: Calculated video height \(height) for width \(width)")
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
                        logger.info("🎥 Navigation - Selected video ID: \(video.id), Index: \(index), Total Videos: \(viewModel.videos.count)")
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
            logger.info("📱 Grid initialized with \(gridVideos.count) videos")
        }
        .onChange(of: viewModel.videos) { _, newVideos in
            withAnimation(.spring()) {
                gridVideos = newVideos
                logger.info("🔄 Grid updated with \(gridVideos.count) videos")
            }
        }
    }
    
    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(gridVideos.enumerated()), id: \.element.id) { index, video in
                gridItem(video: video, index: index)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }
    
    private func gridItem(video: Video, index: Int) -> some View {
        let isReplacing = video.id == viewModel.replacingVideoId
        let isLoading = isReplacing || viewModel.isLoadingVideo(video.id) || loadingSlots.contains(index)
        let isPreloadingThumbnail = preloadingThumbnails.contains(index)
        let isBeingDragged = video.id == swipingVideoId
        let isPartOfMultiSwipe = swipingVideos.contains(video.id)
        
        if isLoading {
            logger.debug("⏳ GRID ITEM: Loading state for video \(video.id) at index \(index)")
        }
        if isPreloadingThumbnail {
            logger.debug("🔄 GRID ITEM: Preloading thumbnail for video \(video.id) at index \(index)")
        }
        
        return AsyncImage(url: video.thumbnailUrl.flatMap { URL(string: $0) }) { phase in
            ZStack {
                switch phase {
                case .empty:
                    LoadingView(message: isPreloadingThumbnail ? "Preloading..." : "Loading thumbnail...")
                    .onAppear {
                        logger.debug("⏳ THUMBNAIL: Started loading for video \(video.id)")
                    }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(9/16, contentMode: .fill)
                        .onAppear {
                            logger.debug("✅ THUMBNAIL: Successfully loaded for video \(video.id)")
                        }
                case .failure:
                    LoadingView(message: "Failed to load", isError: true)
                        .onAppear {
                            logger.error("❌ THUMBNAIL: Failed to load for video \(video.id)")
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
                            logger.debug("🔄 SWIPE: Single video swipe in progress - Video: \(video.id), Offset: \(value.translation.height)")
                            
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
                                logger.debug("🗑️ SWIPE: Removing single video \(video.id) after successful swipe")
                                triggerHapticFeedback()
                                
                                Task {
                                    do {
                                        loadingSlots.insert(index)
                                        logger.debug("⏳ LOADING: Started loading state for index \(index)")
                                        try await viewModel.removeVideo(video.id)
                                        logger.debug("✅ REMOVAL: Completed removal of video \(video.id)")
                                        loadingSlots.remove(index)
                                        logger.debug("✨ CLEANUP: Cleared loading state for index \(index)")
                                    } catch {
                                        logger.error("❌ Failed to remove video: \(error.localizedDescription)")
                                        loadingSlots.remove(index)
                                        showError = true
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            } else {
                                logger.debug("↩️ SWIPE: Cancelled swipe for video \(video.id)")
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
    
    private func fallbackVideoImage(video: Video, width: CGFloat, height: CGFloat) -> some View {
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
        
        preloadingIndex = index
        
        do {
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
            preloadingIndex = nil
        } catch {
            preloadingIndex = nil
            errorMessage = error.localizedDescription
            showError = true
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
        logger.debug("🎨 OPACITY: Calculated opacity \(opacity) for translation \(translation)")
        return opacity
    }
    
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.safeImpactOccurred()
        logger.debug("📳 HAPTIC: Triggered feedback")
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
        logger.debug("🔄 SWIPE: Multi-swipe in progress - Location: \(locationDesc), Offset: \(value.translation.height)")
        
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
                logger.debug("👆 SWIPE: Affecting horizontal videos at indices \(index) and \(index + 1)")
            }
        case .vertical(let index):
            // For vertical gaps, affect videos above and below
            if index < gridVideos.count {
                swipingVideos = [gridVideos[index].id]
                if index + 2 < gridVideos.count {
                    swipingVideos.insert(gridVideos[index + 2].id)
                }
                logger.debug("👆 SWIPE: Affecting vertical videos at indices \(index) and \(index + 2)")
            }
        case .center:
            // For center point, affect all four videos
            swipingVideos = Set(gridVideos.prefix(4).map { $0.id })
            logger.debug("👆 SWIPE: Affecting all four videos in grid")
        }
    }
    
    private func handleGapDragEnd(_ value: DragGesture.Value) {
        let threshold: CGFloat = -90 // Swipe up threshold
        let swipePercentage = abs(value.translation.height) / UIScreen.main.bounds.height
        
        if swipePercentage >= threshold && value.translation.height < 0 {
            // Trigger haptic feedback
            triggerHapticFeedback()
            logger.debug("📳 FEEDBACK: Triggered haptic for successful multi-swipe")
            
            // Remove affected videos simultaneously
            Task {
                do {
                    for videoId in swipingVideos {
                        try await viewModel.removeVideo(videoId)
                    }
                } catch {
                    showError = true
                    errorMessage = error.localizedDescription
                    logger.error("❌ Failed to remove videos: \(error.localizedDescription)")
                }
            }
        }
        
        // Reset state
        withAnimation(.spring()) {
            multiSwipeOffset = 0
            multiSwipeOpacity = 1
            swipingVideos.removeAll()
            swipingGapLocation = nil
            isSwipingGap = false
        }
    }
}

struct VideoGridItem: View {
    let video: Video
    let index: Int
    @ObservedObject var viewModel: VideoViewModel
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeOpacity: Double = 1.0
    @State private var isSwipeInProgress = false
    
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.safeImpactOccurred()
        logger.debug("📳 HAPTIC: Triggered feedback")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video thumbnail or placeholder
                Group {
                    if let thumbnailUrl = video.thumbnailUrl.flatMap({ URL(string: $0) }) {
                        AsyncImage(url: thumbnailUrl) { phase in
                            switch phase {
                            case .empty:
                                LoadingPlaceholder()
                            case .success(let image):
                                image.resizable()
                                     .aspectRatio(contentMode: .fill)
                            case .failure:
                                ErrorPlaceholder()
                            @unknown default:
                                LoadingPlaceholder()
                            }
                        }
                    } else {
                        LoadingPlaceholder()
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                
                // Loading overlay
                if viewModel.loadingStates.contains(index) {
                    Color.black.opacity(0.7)
                    LoadingIndicator()
                }
                
                // Transition overlay
                if case .removing(video.id) = viewModel.transitionState {
                    Color.black.opacity(0.5)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .offset(y: swipeOffset)
            .opacity(swipeOpacity)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleDragChange(value)
                    }
                    .onEnded { value in
                        handleDragEnd(value)
                    }
            )
        }
    }
    
    private func handleDragChange(_ value: DragGesture.Value) {
        guard !viewModel.loadingStates.contains(index) else { return }
        
        isSwipeInProgress = true
        swipeOffset = value.translation.height
        
        // Update opacity based on swipe distance
        let maxDistance: CGFloat = 200
        let progress = min(abs(value.translation.height) / maxDistance, 1.0)
        swipeOpacity = 1.0 - progress * 0.7
        
        logger.debug("🔄 SWIPE: Progress \(Int(progress * 100))% for video \(video.id)")
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        guard !viewModel.loadingStates.contains(index) else { return }
        
        let threshold: CGFloat = -90 // Swipe up threshold
        
        if value.translation.height < threshold {
            // Trigger haptic feedback
            triggerHapticFeedback()
            
            // Remove video
            Task {
                do {
                    try await viewModel.removeVideo(video.id)
                    
                    // Reset state with animation
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        swipeOffset = 0
                        swipeOpacity = 1
                    }
                } catch {
                    // Reset on error
                    withAnimation(.spring()) {
                        swipeOffset = 0
                        swipeOpacity = 1
                    }
                }
            }
        } else {
            // Reset position if threshold not met
            withAnimation(.spring()) {
                swipeOffset = 0
                swipeOpacity = 1
            }
        }
        
        isSwipeInProgress = false
    }
}

struct LoadingPlaceholder: View {
    var body: some View {
        Color.gray.opacity(0.3)
            .overlay(
                ProgressView()
                    .scaleEffect(1.5)
            )
    }
}

struct ErrorPlaceholder: View {
    var body: some View {
        Color.red.opacity(0.3)
            .overlay(
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.white)
                    .font(.largeTitle)
            )
    }
}

struct LoadingIndicator: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .foregroundColor(.white)
                .font(.caption)
        }
    }
}

#Preview {
    InspirationsGridView()
} 