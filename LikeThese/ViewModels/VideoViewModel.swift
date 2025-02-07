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
    private var videoSequence: [Int: Video] = [:] // Track video sequence
    private var videoBuffer: [Video] = [] // Buffer for extra videos
    private let minBufferSize = 4 // Minimum number of videos to keep in buffer
    private let maxBufferSize = 8 // Maximum buffer size
    
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
            // Fetch initial videos plus buffer
            let initialVideos = try await firestoreService.fetchInitialVideos(limit: pageSize + minBufferSize)
            logger.debug("✅ Loaded \(initialVideos.count) initial videos")
            
            // Split into visible videos and buffer
            let visibleVideos = Array(initialVideos.prefix(pageSize))
            videoBuffer = Array(initialVideos.dropFirst(pageSize))
            
            // Store initial sequence
            for (index, video) in visibleVideos.enumerated() {
                videoSequence[index] = video
            }
            
            videos = visibleVideos
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
            // First check buffer
            if !videoBuffer.isEmpty {
                let neededCount = min(pageSize - videos.count, videoBuffer.count)
                let bufferedVideos = Array(videoBuffer.prefix(neededCount))
                videoBuffer.removeFirst(neededCount)
                
                var updatedVideos = videos
                for video in bufferedVideos {
                    updatedVideos.append(video)
                    videoSequence[updatedVideos.count - 1] = video
                }
                videos = updatedVideos
            }
            
            // Replenish buffer if needed
            if videoBuffer.count < minBufferSize {
                let bufferNeeded = maxBufferSize - videoBuffer.count
                for _ in 0..<bufferNeeded {
                    let newVideo = try await firestoreService.fetchRandomVideo()
                    videoBuffer.append(newVideo)
                }
                logger.debug("✅ Replenished buffer with \(bufferNeeded) videos")
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
                replacingVideoId = videoId
                
                // Try to get replacement from buffer first
                var newVideo: Video
                if let bufferedVideo = videoBuffer.first {
                    newVideo = bufferedVideo
                    videoBuffer.removeFirst()
                } else {
                    // Fetch new video if buffer is empty
                    newVideo = try await firestoreService.fetchRandomVideo()
                }
                
                // Atomic update
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                
                // Update sequence
                videoSequence[index] = newVideo
                
                videos = updatedVideos
                replacingVideoId = nil
                
                // Replenish buffer asynchronously
                Task {
                    if videoBuffer.count < minBufferSize {
                        do {
                            let newBufferVideo = try await firestoreService.fetchRandomVideo()
                            videoBuffer.append(newBufferVideo)
                        } catch {
                            logger.error("❌ Error replenishing buffer: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                self.error = error
                replacingVideoId = nil
            }
        }
    }
} 