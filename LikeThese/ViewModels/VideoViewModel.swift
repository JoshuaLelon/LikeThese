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
    private let minBufferSize = 8 // Increased from 4 to handle multi-remove
    private let maxBufferSize = 16 // Increased from 8 to handle multi-remove
    
    // Add state tracking
    private var preservedState: [String: Any] = [:]
    private var cachedThumbnails: [String: URL] = [:]
    private var lastKnownIndices: [String: Int] = [:]
    
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
    
    func preserveCurrentState() {
        self.preservedState["videos"] = self.videos
        self.preservedState["videoSequence"] = self.videoSequence
        self.preservedState["lastKnownIndices"] = self.lastKnownIndices
        logger.info("📦 STATE: Preserved current grid state with \(self.videos.count) videos")
    }
    
    func restorePreservedState() {
        if let preservedVideos = self.preservedState["videos"] as? [Video] {
            self.videos = preservedVideos
            if let sequence = self.preservedState["videoSequence"] as? [Int: Video] {
                self.videoSequence = sequence
            }
            if let indices = self.preservedState["lastKnownIndices"] as? [String: Int] {
                self.lastKnownIndices = indices
            }
            logger.info("📦 STATE: Restored grid state with \(self.videos.count) videos")
        }
    }
    
    func loadMoreVideosIfNeeded(currentIndex: Int) async {
        guard currentIndex >= videos.count - 3 && !isLoadingMore else { return }
        
        isLoadingMore = true
        do {
            let existingCount = videos.count
            let neededCount = max(0, pageSize - existingCount)
            
            if neededCount > 0 {
                var newVideos = videos // Preserve existing videos
                
                // First check buffer
                while newVideos.count < pageSize && !videoBuffer.isEmpty {
                    newVideos.append(videoBuffer.removeFirst())
                }
                
                // If still need more, fetch from network
                let remainingNeeded = pageSize - newVideos.count
                if remainingNeeded > 0 {
                    for _ in 0..<remainingNeeded {
                        let video = try await firestoreService.fetchRandomVideo()
                        newVideos.append(video)
                        // Cache the video's position
                        lastKnownIndices[video.id] = newVideos.count - 1
                    }
                }
                
                await MainActor.run {
                    videos = newVideos
                    // Preserve sequence
                    for (index, video) in newVideos.enumerated() {
                        videoSequence[index] = video
                    }
                }
            }
            
            // Replenish buffer in background
            Task {
                await replenishBuffer()
            }
        } catch {
            self.error = error
            logger.error("❌ Failed to load more videos: \(error.localizedDescription)")
        }
        isLoadingMore = false
    }
    
    private func replenishBuffer() async {
        guard self.videoBuffer.count < self.minBufferSize else { return }
        
        do {
            let needed = self.maxBufferSize - self.videoBuffer.count
            for _ in 0..<needed {
                let video = try await self.firestoreService.fetchRandomVideo()
                self.videoBuffer.append(video)
            }
            logger.info("🔄 BUFFER: Replenished video buffer to \(self.videoBuffer.count) videos")
        } catch {
            logger.error("❌ BUFFER: Failed to replenish video buffer: \(error.localizedDescription)")
        }
    }
    
    func getVideoAtIndex(_ index: Int) -> Video? {
        if index < videos.count {
            return videos[index]
        }
        return videoSequence[index]
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
                            let newBufferVideo = try await self.firestoreService.fetchRandomVideo()
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
    
    func removeMultipleVideos(_ videoIds: [String]) async {
        do {
            // Set loading state for all videos
            await MainActor.run {
                for videoId in videoIds {
                    loadingVideoIds.insert(videoId)
                }
            }
            
            // Fetch all replacement videos first
            var replacements: [Video] = []
            for _ in videoIds {
                if let bufferedVideo = videoBuffer.first {
                    replacements.append(bufferedVideo)
                    videoBuffer.removeFirst()
                } else {
                    let newVideo = try await self.firestoreService.fetchRandomVideo()
                    replacements.append(newVideo)
                }
            }
            
            // Perform atomic update
            await MainActor.run {
                var updatedVideos = videos
                for (index, videoId) in videoIds.enumerated() {
                    if let videoIndex = updatedVideos.firstIndex(where: { $0.id == videoId }) {
                        updatedVideos.remove(at: videoIndex)
                        updatedVideos.insert(replacements[index], at: videoIndex)
                        videoSequence[videoIndex] = replacements[index]
                    }
                }
                videos = updatedVideos
                
                // Clear loading states
                for videoId in videoIds {
                    loadingVideoIds.remove(videoId)
                }
            }
            
            // Replenish buffer asynchronously
            Task {
                if videoBuffer.count < minBufferSize {
                    do {
                        let newBufferVideos = try await withThrowingTaskGroup(of: Video.self) { group in
                            for _ in 0..<(minBufferSize - videoBuffer.count) {
                                group.addTask {
                                    try await self.firestoreService.fetchRandomVideo()
                                }
                            }
                            
                            var videos: [Video] = []
                            for try await video in group {
                                videos.append(video)
                            }
                            return videos
                        }
                        
                        await MainActor.run {
                            videoBuffer.append(contentsOf: newBufferVideos)
                        }
                    } catch {
                        logger.error("❌ Error replenishing buffer: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error
                for videoId in videoIds {
                    loadingVideoIds.remove(videoId)
                }
            }
        }
    }
} 