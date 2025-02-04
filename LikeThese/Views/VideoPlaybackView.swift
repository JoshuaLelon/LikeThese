import SwiftUI
import AVKit
import os
import FirebaseFirestore

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoPlayback")

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
            if viewModel.videos.isEmpty {
                ProgressView("Loading videos...")
                    .onAppear {
                        logger.debug("⌛️ Showing loading indicator")
                    }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                            if let url = URL(string: video.url) {
                                VideoPlayerView(url: url, index: index, videoManager: videoManager)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .id(index)
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
                        Task {
                            await viewModel.loadMoreVideosIfNeeded(currentIndex: index)
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .all)
        .statusBar(hidden: true)
        .onAppear {
            logger.debug("🎬 VideoPlaybackView appeared, loading initial videos")
            Task {
                await viewModel.loadInitialVideos()
            }
        }
    }
}

// VideoManager class has been moved to VideoManager.swift

// VideoViewModel class
class VideoViewModel: ObservableObject {
    @Published var videos: [Video] = []
    private let firestoreService = FirestoreService.shared
    private let pageSize = 5
    
    @MainActor
    func loadInitialVideos() async {
        logger.debug("📥 Starting initial video load")
        do {
            // Load initial set of videos
            let initialVideos = try await firestoreService.fetchInitialVideos(limit: pageSize)
            logger.debug("✅ Loaded \(initialVideos.count) initial videos")
            videos = initialVideos
        } catch {
            logger.error("❌ Error loading initial videos: \(error.localizedDescription)")
            print("Error loading initial videos: \(error)")
        }
    }
    
    @MainActor
    func loadMoreVideosIfNeeded(currentIndex: Int) async {
        // Load more videos when user is 2 videos away from the end
        if currentIndex >= videos.count - 2 {
            logger.debug("📥 Loading more videos")
            do {
                let newVideos = try await firestoreService.fetchMoreVideos(
                    after: videos.last?.id ?? "",
                    limit: pageSize
                )
                logger.debug("✅ Loaded \(newVideos.count) more videos")
                videos.append(contentsOf: newVideos)
            } catch {
                logger.error("❌ Error loading more videos: \(error.localizedDescription)")
                print("Error loading more videos: \(error)")
            }
        }
    }
}

struct VideoPlaybackView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlaybackView()
    }
} 