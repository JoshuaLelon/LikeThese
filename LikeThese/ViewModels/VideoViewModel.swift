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
    
    // Add video removal functionality
    func removeVideo(_ videoId: String) async {
        logger.debug("🗑️ Removing video: \(videoId)")
        
        // Find and remove the video
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            // Remove the video first
            videos.remove(at: index)
            logger.debug("✅ Removed video at index \(index)")
            
            // Load a replacement video
            do {
                // Start loading the replacement immediately
                let newVideoTask = Task { try await firestoreService.fetchRandomVideo() }
                
                // Give time for removal animation
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                // Get the new video
                let newVideo = try await newVideoTask.value
                logger.debug("✅ Loaded replacement video: \(newVideo.id)")
                
                // Insert with animation
                await MainActor.run {
                    withAnimation(.spring()) {
                        videos.insert(newVideo, at: index)
                    }
                }
            } catch {
                logger.error("❌ Error loading replacement video: \(error.localizedDescription)")
                self.error = error
            }
        }
    }
} 