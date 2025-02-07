import Foundation
import os
import FirebaseFirestore
import SwiftUI

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoViewModel")

@MainActor
class VideoViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var error: Error?
    @Published var replacingVideoId: String?
    @Published private var loadingVideoIds: Set<String> = []
    private let firestoreService = FirestoreService.shared
    private let pageSize = 4 // Only load 4 at a time
    
    func isLoadingVideo(_ videoId: String) -> Bool {
        return loadingVideoIds.contains(videoId)
    }
    
    func setLoadingState(for videoId: String, isLoading: Bool) {
        if isLoading {
            loadingVideoIds.insert(videoId)
        } else {
            loadingVideoIds.remove(videoId)
        }
    }
    
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
        // Load a batch of videos when we're 3 videos away from the end
        if currentIndex >= videos.count - 3 && !isLoadingMore {
            logger.debug("📥 Loading batch of videos after index \(currentIndex)")
            isLoadingMore = true
            error = nil
            
            do {
                // Load a batch of random videos
                var newVideos: [Video] = []
                for _ in 0..<pageSize {
                    let newVideo = try await firestoreService.fetchRandomVideo()
                    newVideos.append(newVideo)
                }
                logger.debug("✅ Loaded \(newVideos.count) random videos")
                videos.append(contentsOf: newVideos)
            } catch {
                logger.error("❌ Error loading random videos: \(error.localizedDescription)")
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
    
    // Add video removal functionality
    func removeVideo(_ videoId: String) async {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            do {
                // Set loading state
                replacingVideoId = videoId
                
                // Fetch new video first
                let newVideo = try await firestoreService.fetchRandomVideo()
                
                // Atomic update
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                videos = updatedVideos
                replacingVideoId = nil
            } catch {
                self.error = error
                replacingVideoId = nil
            }
        }
    }
} 