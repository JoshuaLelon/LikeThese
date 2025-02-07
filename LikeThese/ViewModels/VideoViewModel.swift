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
    private let firestoreService: FirestoreService
    private let pageSize = 4 // Only load 4 at a time
    private var videoSequence: [Int: Video] = [:] // Track video sequence
    
    init(firestoreService: FirestoreService = FirestoreService.shared) {
        self.firestoreService = firestoreService
    }
    
    func isLoadingVideo(_ videoId: String) -> Bool {
        return replacingVideoId == videoId
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
            let initialVideos = try await firestoreService.fetchInitialVideos(limit: pageSize)
            logger.debug("✅ Loaded \(initialVideos.count) initial videos")
            
            // Store initial sequence
            for (index, video) in initialVideos.enumerated() {
                videoSequence[index] = video
            }
            
            videos = initialVideos
        } catch {
            logger.error("❌ Error loading initial videos: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoading = false
    }
    
    func loadMoreVideosIfNeeded(currentIndex: Int) async {
        guard currentIndex >= videos.count - 3 && !isLoadingMore else { return }
        
        logger.debug("📥 Loading more videos after index \(currentIndex)")
        isLoadingMore = true
        error = nil
        
        do {
            // Keep existing videos
            var updatedVideos = videos
            
            // Calculate how many new videos we need
            let neededCount = pageSize - updatedVideos.count
            
            if neededCount > 0 {
                for _ in 0..<neededCount {
                    let newVideo = try await firestoreService.fetchRandomVideo()
                    updatedVideos.append(newVideo)
                    // Store in sequence
                    videoSequence[updatedVideos.count - 1] = newVideo
                }
                
                logger.debug("✅ Added \(neededCount) new videos")
                
                // Update atomically
                videos = updatedVideos
            }
        } catch {
            logger.error("❌ Error loading more videos: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoadingMore = false
    }
    
    func getPreviousVideo(from index: Int) -> Video? {
        return videoSequence[index - 1]
    }
    
    func getNextVideo(from index: Int) -> Video? {
        return videoSequence[index + 1]
    }
    
    // Load a random video at a specific index
    func loadRandomVideo(at index: Int) async throws -> Video {
        let video = try await firestoreService.fetchRandomVideo()
        await MainActor.run {
            if index < videos.count {
                videos[index] = video
                videoSequence[index] = video
            }
        }
        return video
    }
    
    // Add autoplay functionality
    func appendAutoplayVideo(_ video: Video) {
        logger.debug("📥 Appending autoplay video: \(video.id)")
        let nextIndex = videos.count
        videos.append(video)
        videoSequence[nextIndex] = video
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