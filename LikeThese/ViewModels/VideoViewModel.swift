import Foundation
import os
import FirebaseFirestore

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoViewModel")

@MainActor
class VideoViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var error: Error?
    private let firestoreService = FirestoreService.shared
    private let pageSize = 5
    
    func loadInitialVideos() async {
        logger.debug("📥 Starting initial video load")
        isLoading = true
        error = nil
        
        do {
            // Load initial set of videos
            let initialVideos = try await firestoreService.fetchInitialVideos(limit: pageSize)
            logger.debug("✅ Loaded \(initialVideos.count) initial videos")
            videos = initialVideos
        } catch {
            logger.error("❌ Error loading initial videos: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoading = false
    }
    
    func loadMoreVideosIfNeeded(currentIndex: Int) async {
        // Load more videos when user is 2 videos away from the end
        if currentIndex >= videos.count - 2 && !isLoadingMore {
            logger.debug("📥 Loading more videos")
            isLoadingMore = true
            error = nil
            
            do {
                let newVideos = try await firestoreService.fetchMoreVideos(
                    after: videos.last?.id ?? "",
                    limit: pageSize
                )
                logger.debug("✅ Loaded \(newVideos.count) more videos")
                videos.append(contentsOf: newVideos)
            } catch {
                logger.error("❌ Error loading more videos: \(error.localizedDescription)")
                self.error = error
            }
            
            isLoadingMore = false
        }
    }
    
    // Add autoplay functionality
    func appendAutoplayVideo(_ video: Video) {
        logger.debug("📥 Appending autoplay video: \(video.id)")
        videos.append(video)
    }
} 