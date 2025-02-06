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
    private let pageSize = 4 // Only load 4 at a time
    
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
        // Always try to load a new random video when we're 3 videos away from the end
        if currentIndex >= videos.count - 3 && !isLoadingMore {
            logger.debug("📥 Loading random video after index \(currentIndex)")
            isLoadingMore = true
            error = nil
            
            do {
                // Load a single random video
                let newVideo = try await firestoreService.fetchRandomVideo()
                logger.debug("✅ Loaded random video: \(newVideo.id)")
                videos.append(newVideo)
            } catch {
                logger.error("❌ Error loading random video: \(error.localizedDescription)")
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