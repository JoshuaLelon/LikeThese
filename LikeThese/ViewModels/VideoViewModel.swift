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
    @Published private var gridState = GridState()
    @Published private var preloadingThumbnails: Set<Int> = []
    private let firestoreService: FirestoreService
    private let pageSize = 4 // Only load 4 at a time
    private var videoSequence: [Int: Video] = [:] // Track video sequence
    private let maxSwipesBeforeReset = 10
    private let thumbnailCache = NSCache<NSString, UIImage>()
    
    private struct GridState {
        var replacingVideoId: String?
        var loadingIndices: Set<Int> = []
        var swipeCount: Int = 0
        var lastSwipeTime: Date?
        
        mutating func reset() {
            replacingVideoId = nil
            loadingIndices.removeAll()
            swipeCount = 0
            lastSwipeTime = nil
        }
    }
    
    init(firestoreService: FirestoreService = FirestoreService.shared) {
        self.firestoreService = firestoreService
    }
    
    func isLoadingVideo(_ videoId: String) -> Bool {
        if self.replacingVideoId == videoId { return true }
        if let index = self.videos.firstIndex(where: { $0.id == videoId }) {
            return self.gridState.loadingIndices.contains(index)
        }
        return false
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
    
    private func preloadThumbnail(for video: Video, at index: Int) async {
        guard !preloadingThumbnails.contains(index),
              let thumbnailUrl = video.thumbnailUrl,
              let url = URL(string: thumbnailUrl),
              thumbnailCache.object(forKey: thumbnailUrl as NSString) == nil else {
            return
        }
        
        preloadingThumbnails.insert(index)
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                thumbnailCache.setObject(image, forKey: thumbnailUrl as NSString)
                logger.debug("✅ THUMBNAIL: Successfully preloaded for index \(index)")
            }
        } catch {
            logger.error("❌ THUMBNAIL: Failed to preload for index \(index): \(error.localizedDescription)")
        }
        
        preloadingThumbnails.remove(index)
    }
    
    func preloadThumbnails(startingAt index: Int, count: Int = 2) {
        let endIndex = min(index + count, videos.count)
        guard index < endIndex else { return }
        
        Task {
            for i in index..<endIndex {
                await preloadThumbnail(for: videos[i], at: i)
            }
        }
    }
    
    func getCachedThumbnail(for video: Video) -> UIImage? {
        guard let thumbnailUrl = video.thumbnailUrl else { return nil }
        return thumbnailCache.object(forKey: thumbnailUrl as NSString)
    }
    
    // Update removeVideo to preload thumbnails
    func removeVideo(_ videoId: String) async {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            do {
                // Update grid state
                gridState.swipeCount += 1
                gridState.lastSwipeTime = Date()
                gridState.loadingIndices.insert(index)
                replacingVideoId = videoId
                
                // Fetch new video first
                let newVideo = try await firestoreService.fetchRandomVideo()
                
                // Start preloading thumbnail while updating
                Task {
                    await preloadThumbnail(for: newVideo, at: index)
                }
                
                // Atomic update
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                videos = updatedVideos
                videoSequence[index] = newVideo
                
                // Preload next thumbnails
                preloadThumbnails(startingAt: index + 1)
                
                // Clean up state
                gridState.loadingIndices.remove(index)
                if gridState.replacingVideoId == videoId {
                    gridState.replacingVideoId = nil
                    replacingVideoId = nil
                }
                
                // Verify grid state
                verifyGridState()
            } catch {
                // Clean up on error
                gridState.loadingIndices.remove(index)
                gridState.replacingVideoId = nil
                replacingVideoId = nil
                self.error = error
            }
        }
    }
    
    // Add batch video removal functionality
    func removeVideos(_ videoIds: [String]) async {
        let indices = videoIds.compactMap { videoId in
            videos.firstIndex(where: { $0.id == videoId })
        }.sorted()
        
        guard !indices.isEmpty else { return }
        
        do {
            // Update grid state
            for index in indices {
                gridState.loadingIndices.insert(index)
            }
            gridState.swipeCount += 1
            gridState.lastSwipeTime = Date()
            
            // Fetch all replacement videos first
            var newVideos = [(index: Int, video: Video)]()
            for index in indices {
                let video = try await firestoreService.fetchRandomVideo()
                newVideos.append((index, video))
                
                // Start preloading thumbnail
                Task {
                    await preloadThumbnail(for: video, at: index)
                }
            }
            
            // Atomic update
            var updatedVideos = videos
            for (index, video) in newVideos.reversed() {
                updatedVideos.remove(at: index)
                updatedVideos.insert(video, at: index)
                videoSequence[index] = video
            }
            videos = updatedVideos
            
            // Preload next thumbnails
            if let lastIndex = indices.last {
                preloadThumbnails(startingAt: lastIndex + 1)
            }
            
            // Clean up state
            for index in indices {
                gridState.loadingIndices.remove(index)
            }
            replacingVideoId = nil
            
            // Verify grid state
            verifyGridState()
        } catch {
            // Clean up on error
            for index in indices {
                gridState.loadingIndices.remove(index)
            }
            replacingVideoId = nil
            self.error = error
        }
    }
    
    func verifyPlayerReadiness(for index: Int, videoManager: VideoManager) async throws {
        guard let video = videos[safe: index],
              let url = URL(string: video.url) else {
            throw VideoError.invalidVideo
        }
        
        // Set loading state
        replacingVideoId = video.id
        
        do {
            // Prepare for playback
            videoManager.prepareForPlayback(at: index)
            
            // Preload with verification
            try await videoManager.preloadVideo(url: url, forIndex: index)
            
            // Verify player is ready with timeout
            try await withTimeout(seconds: 5.0) {
                while true {
                    if let player = videoManager.player(for: index),
                       let currentItem = player.currentItem,
                       currentItem.status == .readyToPlay,
                       currentItem.isPlaybackLikelyToKeepUp {
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }
            }
            
            replacingVideoId = nil
        } catch {
            replacingVideoId = nil
            throw error
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw VideoError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func logGridStateReset(_ swipeCount: Int) {
        logger.debug("🔄 Resetting grid state after \(swipeCount) swipes")
    }
    
    private func verifyGridState() {
        // Verify video sequence integrity
        for (index, video) in self.videos.enumerated() {
            if self.videoSequence[index]?.id != video.id {
                logger.warning("⚠️ Grid state mismatch at index \(index), fixing...")
                self.videoSequence[index] = video
            }
        }
        
        // Clean up stale sequence entries
        let validIndices = Set(0..<self.videos.count)
        let filteredSequence = self.videoSequence.filter { validIndices.contains($0.key) }
        self.videoSequence = filteredSequence
        
        // Reset grid state if needed
        let currentSwipeCount = self.gridState.swipeCount
        let shouldReset = currentSwipeCount >= self.maxSwipesBeforeReset
        
        if shouldReset {
            logGridStateReset(currentSwipeCount)
            self.gridState.reset()
        }
    }
}

enum VideoError: Error {
    case invalidVideo
    case timeout
    case playerNotReady
} 