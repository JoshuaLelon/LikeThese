import SwiftUI
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "InspirationsGrid")

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
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
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
        .onChange(of: viewModel.videos) { newVideos in
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
        let isLoading = isReplacing || viewModel.isLoadingVideo(video.id)
        let isBeingDragged = video.id == swipingVideoId
        let isPartOfMultiSwipe = swipingVideos.contains(video.id)
        
        return ZStack {
            if let cachedImage = viewModel.getCachedThumbnail(for: video) {
                Image(uiImage: cachedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                AsyncImage(url: video.thumbnailUrl.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .empty:
                        LoadingView(message: "Loading thumbnail...")
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        LoadingView(message: "Failed to load", isError: true)
                    @unknown default:
                        LoadingView(message: "Loading...")
                    }
                }
            }
            
            if isLoading {
                Color.black.opacity(0.7)
                VStack {
                    ProgressView()
                        .tint(.white)
                    Text(isReplacing ? "Loading new video..." : "Removing...")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(.top, 4)
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: isLoading)
        .offset(y: isBeingDragged ? swipeOffset : (isPartOfMultiSwipe ? multiSwipeOffset : 0))
        .opacity(isPartOfMultiSwipe ? multiSwipeOpacity : (isBeingDragged ? swipeOpacity : 1.0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isSwipingGap && !isLoading {
                        isSwipeInProgress = true
                        swipingVideoId = video.id
                        swipeOffset = value.translation.height
                        
                        // Update opacity based on swipe progress
                        withAnimation(.easeInOut(duration: 0.1)) {
                            swipeOpacity = calculateOpacity(for: value.translation.height, threshold: -45)
                        }
                    }
                }
                .onEnded { value in
                    if !isSwipingGap && !isLoading {
                        let threshold: CGFloat = -45 // Reduced from -90 to -45 for easier swipes
                        if value.translation.height < threshold {
                            logger.debug("🗑️ SWIPE: Removing single video \(video.id) after successful swipe")
                            triggerHapticFeedback()
                            
                            Task {
                                loadingSlots.insert(index)
                                logger.debug("⏳ LOADING: Started loading state for index \(index)")
                                await viewModel.removeVideo(video.id)
                                logger.debug("✅ REMOVAL: Completed removal of video \(video.id)")
                                loadingSlots.remove(index)
                                logger.debug("✨ CLEANUP: Cleared loading state for index \(index)")
                            }
                        } else {
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
        .onAppear {
            // Preload next thumbnails when this item appears
            viewModel.preloadThumbnails(startingAt: index)
        }
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
        preloadingIndex = index
        
        do {
            // Verify player readiness first
            try await viewModel.verifyPlayerReadiness(for: index, videoManager: videoManager)
            
            // Only navigate if we have valid video
            if let video = gridVideos[safe: index] {
                selectedVideo = video
                selectedIndex = index
                isVideoPlaybackActive = true
            }
            preloadingIndex = nil
        } catch {
            preloadingIndex = nil
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func calculateOpacity(for translation: CGFloat, threshold: CGFloat) -> CGFloat {
        let progress = min(abs(translation) / (threshold * UIScreen.main.bounds.height), 1.0)
        let opacity = 1.0 - (progress * 0.5)
        logger.debug("🎨 OPACITY: Calculated opacity \(opacity) for translation \(translation)")
        return opacity
    }
    
    private func triggerHapticFeedback() {
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
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
        let threshold = swipingGapLocation == .center ? 
            fourVideoSwipeThreshold : twoVideoSwipeThreshold
        let swipeDistance = abs(value.translation.height)
        let screenHeight = UIScreen.main.bounds.height
        let swipePercentage = swipeDistance / screenHeight
        
        logger.debug("🔄 SWIPE: Multi-swipe ended - Distance: \(swipeDistance), Percentage: \(swipePercentage * 100)%")
        
        if swipePercentage >= threshold && value.translation.height < 0 {
            // Trigger haptic feedback
            triggerHapticFeedback()
            logger.debug("📳 FEEDBACK: Triggered haptic for successful multi-swipe")
            
            // Remove affected videos simultaneously
            Task {
                // Convert to array to maintain order
                let videoIds = Array(swipingVideos)
                let gridIndices = videoIds.compactMap { videoId in
                    gridVideos.firstIndex(where: { $0.id == videoId })
                }
                
                logger.debug("🗑️ REMOVAL: Starting batch removal of \(videoIds.count) videos")
                
                // Mark all videos as loading
                for index in gridIndices {
                    loadingSlots.insert(index)
                }
                
                // Animate all videos up simultaneously
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    multiSwipeOffset = -UIScreen.main.bounds.height
                    multiSwipeOpacity = 0
                }
                
                // Small delay to let animation complete
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                // Remove all videos in a single batch
                await viewModel.removeVideos(videoIds)
                
                // Clear loading states
                loadingSlots.removeAll()
                preloadingThumbnails.removeAll()
                logger.debug("✨ CLEANUP: Cleared all loading states and preloading flags")
            }
        } else {
            // Reset state with animation if swipe wasn't far enough
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                multiSwipeOffset = 0
                multiSwipeOpacity = 1.0
            }
        }
        
        isSwipingGap = false
        swipingGapLocation = nil
        swipingVideos.removeAll()
        logger.debug("🔄 RESET: Cleared multi-swipe state")
    }
}

#Preview {
    InspirationsGridView()
} 