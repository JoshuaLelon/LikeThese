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
                            logger.debug("⌛️ Showing loading indicator")
                        }
                } else if let error = viewModel.error {
                    ErrorView(error: error) {
                        Task {
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
                                                if currentIndex == nil {
                                                    currentIndex = index
                                                }
                                            }
                                        
                                        if viewModel.isLoadingMore && index == viewModel.videos.count - 1 {
                                            ProgressView()
                                                .scaleEffect(1.5)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(Color.black.opacity(0.3))
                                        }
                                    }
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                dragOffset = value.translation.height
                                            }
                                            .onEnded { value in
                                                let threshold = geometry.size.height * 0.3
                                                if abs(value.translation.height) > threshold {
                                                    withAnimation {
                                                        if value.translation.height < 0 {
                                                            // Swipe up
                                                            currentIndex = (currentIndex ?? 0) + 1
                                                            Task {
                                                                await viewModel.loadMoreVideosIfNeeded(currentIndex: currentIndex ?? 0)
                                                            }
                                                        } else {
                                                            // Swipe down
                                                            currentIndex = max(0, (currentIndex ?? 0) - 1)
                                                        }
                                                    }
                                                }
                                                dragOffset = 0
                                            }
                                    )
                                    .highPriorityGesture(
                                        TapGesture()
                                            .onEnded {
                                                videoManager.togglePlayPause(index: index)
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
                            videoManager.pauseAllExcept(index: index)
                            updateVideoObserver()
                            Task {
                                await viewModel.loadMoreVideosIfNeeded(currentIndex: index)
                                // Preload next video if available
                                if index + 1 < viewModel.videos.count,
                                   let nextVideoUrl = URL(string: viewModel.videos[index + 1].url) {
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
            logger.debug("🎬 VideoPlaybackView appeared, loading initial videos")
            Task {
                await viewModel.loadInitialVideos()
            }
            setupVideoCompletion()
        }
    }
    
    func setupVideoCompletion() {
        logger.debug("🔄 Setting up video completion handler")
        // Remove any existing observers first
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        // Observe the current player's item
        if let currentIdx = currentIndex,
           let player = videoManager.currentPlayer(at: currentIdx) {
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] notification in
                logger.debug("📺 Video playback completed")
                
                Task { @MainActor in
                    if let currentVideoId = viewModel.videos[safe: currentIdx]?.id {
                        logger.debug("🎥 Current video ID: \(currentVideoId)")
                        await handleVideoEnd(currentVideoId: currentVideoId)
                    } else {
                        logger.error("❌ Could not get current video ID")
                    }
                }
            }
        }
    }
    
    func handleVideoEnd(currentVideoId: String) async {
        logger.debug("🔄 Handling video end for ID: \(currentVideoId)")
        do {
            let nextVideo = try await FirestoreService.shared.fetchReplacementVideo(excluding: currentVideoId)
            logger.debug("✅ Fetched next video: \(nextVideo.id)")
            
            // Add the new video to the viewModel
            viewModel.appendAutoplayVideo(nextVideo)
            // Update the current index to show the new video
            let newIndex = viewModel.videos.count - 1
            currentIndex = newIndex
            
            // Set up observer for the new video
            setupVideoCompletion()
            
        } catch FirestoreError.emptyVideoCollection {
            logger.debug("ℹ️ No next video available, replaying current video")
            if let currentIdx = currentIndex {
                await videoManager.seekToBeginning(at: currentIdx)
            }
        } catch {
            logger.error("❌ Error fetching next video: \(error.localizedDescription)")
            if let currentIdx = currentIndex {
                await videoManager.seekToBeginning(at: currentIdx)
            }
        }
    }
    
    // Add this to handle player changes
    private func updateVideoObserver() {
        Task { @MainActor in
            setupVideoCompletion()
        }
    }
}

struct VideoPlaybackView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlaybackView()
    }
} 