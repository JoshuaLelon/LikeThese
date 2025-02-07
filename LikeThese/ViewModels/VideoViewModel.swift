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
    
    /// Represents the state of a video transition
    enum VideoTransitionState {
        case none
        case removing(String)  // videoId
        case replacing(String, Video)  // old videoId, new video
        case completed
    }

    @Published private(set) var transitionState: VideoTransitionState = .none
    @Published private(set) var loadingStates: Set<Int> = []
    
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
    func removeVideo(_ videoId: String) async throws {
        guard let index = videos.firstIndex(where: { $0.id == videoId }) else {
            logger.error("❌ REMOVAL: Failed to find video with ID \(videoId)")
            return
        }
        
        // 1. Set removing state
        await MainActor.run {
            transitionState = .removing(videoId)
            loadingStates.insert(index)
        }
        
        do {
            // 2. Fetch replacement video (with retry)
            let newVideo = try await withRetry(maxAttempts: 3) {
                if let buffered = videoBuffer.first {
                    videoBuffer.removeFirst()
                    return buffered
                }
                return try await firestoreService.fetchRandomVideo()
            }
            
            // 3. Update transition state with new video
            await MainActor.run {
                transitionState = .replacing(videoId, newVideo)
            }
            
            // 4. Perform atomic update
            await MainActor.run {
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                videos = updatedVideos
                videoSequence[index] = newVideo
                
                // 5. Clear states
                transitionState = .completed
                loadingStates.remove(index)
            }
            
            // 6. Replenish buffer asynchronously
            Task {
                await replenishBuffer()
            }
            
            logger.debug("✅ REMOVAL: Successfully replaced video \(videoId) with \(newVideo.id)")
        } catch {
            // Reset states on error
            await MainActor.run {
                transitionState = .none
                loadingStates.remove(index)
            }
            logger.error("❌ REMOVAL: Failed to replace video \(videoId): \(error.localizedDescription)")
            throw error
        }
    }
    
    private func withRetry<T>(maxAttempts: Int, operation: () async throws -> T) async throws -> T {
        var attempts = 0
        var lastError: Error?
        
        while attempts < maxAttempts {
            do {
                return try await operation()
            } catch {
                attempts += 1
                lastError = error
                if attempts < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempts)) * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(domain: "com.Gauntlet.LikeThese", code: -1, 
            userInfo: [NSLocalizedDescriptionKey: "Max retry attempts reached"])
    }
    
    private func replenishBuffer() async {
        guard videoBuffer.count < 4 else { return }
        
        do {
            let newVideo = try await firestoreService.fetchRandomVideo()
            await MainActor.run {
                videoBuffer.append(newVideo)
            }
        } catch {
            logger.error("❌ BUFFER: Failed to replenish video buffer: \(error.localizedDescription)")
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