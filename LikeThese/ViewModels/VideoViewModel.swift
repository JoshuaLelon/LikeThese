import Foundation
import FirebaseFirestore
import SwiftUI
import FirebaseFunctions
import FirebaseAuth
import AVKit

@MainActor
class VideoViewModel: ObservableObject {
    @Published var videos: [LikeTheseVideo] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var error: Error?
    @Published var replacingVideoId: String?
    @Published private var loadingVideoIds: Set<String> = []
    @Published var currentVideo: LikeTheseVideo?
    private let firestoreService = FirestoreService.shared
    private let pageSize = 4 // Only load 4 at a time
    private var videoSequence: [Int: LikeTheseVideo] = [:] // Track video sequence
    private var videoBuffer: [LikeTheseVideo] = [] // Buffer for extra videos
    private let minBufferSize = 8 // Increased from 4 to handle multi-remove
    private let maxBufferSize = 16 // Increased from 8 to handle multi-remove
    
    // Add state tracking
    private var preservedState: [String: Any] = [:]
    private var cachedThumbnails: [String: URL] = [:]
    private var lastKnownIndices: [String: Int] = [:]
    
    // Initialize Firebase Functions with custom domain
    private let functions = Functions.functions(region: "us-central1")
    
    private var currentBoardVideos: [LikeTheseVideo] = []
    
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
        print("📥 Starting initial video load")
        isLoading = true
        error = nil
        
        do {
            // Fetch initial videos plus buffer
            let initialVideos = try await firestoreService.fetchInitialVideos(limit: pageSize + minBufferSize)
            print("✅ Loaded \(initialVideos.count) initial videos")
            
            // Split into visible videos and buffer
            let visibleVideos = Array(initialVideos.prefix(pageSize))
            videoBuffer = Array(initialVideos.dropFirst(pageSize))
            
            // Store initial sequence
            for (index, video) in visibleVideos.enumerated() {
                videoSequence[index] = video
            }
            
            videos = visibleVideos
        } catch {
            print("❌ Error loading initial videos: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoading = false
    }
    
    func preserveCurrentState() {
        self.preservedState["videos"] = self.videos
        self.preservedState["videoSequence"] = self.videoSequence
        self.preservedState["lastKnownIndices"] = self.lastKnownIndices
        print("📦 STATE: Preserved current grid state with \(self.videos.count) videos")
    }
    
    func restorePreservedState() {
        if let preservedVideos = self.preservedState["videos"] as? [LikeTheseVideo] {
            self.videos = preservedVideos
            if let sequence = self.preservedState["videoSequence"] as? [Int: LikeTheseVideo] {
                self.videoSequence = sequence
            }
            if let indices = self.preservedState["lastKnownIndices"] as? [String: Int] {
                self.lastKnownIndices = indices
            }
            print("📦 STATE: Restored grid state with \(self.videos.count) videos")
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
            print("❌ Failed to load more videos: \(error.localizedDescription)")
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
            print("🔄 BUFFER: Replenished video buffer to \(self.videoBuffer.count) videos")
        } catch {
            print("❌ BUFFER: Failed to replenish video buffer: \(error.localizedDescription)")
        }
    }
    
    func getVideoAtIndex(_ index: Int) -> LikeTheseVideo? {
        if index < videos.count {
            return videos[index]
        }
        return videoSequence[index]
    }
    
    func getPreviousVideo(from index: Int) -> LikeTheseVideo? {
        return videoSequence[index - 1]
    }
    
    func getNextVideo(from currentIndex: Int) -> LikeTheseVideo? {
        if currentIndex + 1 < videos.count {
            return videos[currentIndex + 1]
        }
        return nil
    }
    
    // Load a random video at a specific index
    func loadRandomVideo(at index: Int) async throws -> LikeTheseVideo {
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
    func appendAutoplayVideo(_ video: LikeTheseVideo) {
        print("📥 Appending autoplay video: \(video.id)")
        let nextIndex = videos.count
        videos.append(video)
        videoSequence[nextIndex] = video
    }
    
    // Add video removal functionality
    func removeVideo(_ videoId: String) async {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            replacingVideoId = videoId
            
            do {
                // Get current videos in grid as board videos
                let boardVideos = videos
                
                // Get a set of candidate videos
                var candidateVideos: [LikeTheseVideo] = []
                for _ in 0..<5 {  // Get 5 candidates
                    do {
                        let video = try await firestoreService.fetchRandomVideo()
                        candidateVideos.append(video)
                    } catch {
                        print("❌ Error fetching candidate video: \(error.localizedDescription)")
                    }
                }
                
                // Make sure we have at least one candidate
                guard !candidateVideos.isEmpty else {
                    throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No candidate videos available"])
                }
                
                // Find least similar video using AI
                let newVideo = try await findLeastSimilarVideo(
                    boardVideos: boardVideos,
                    candidateVideos: candidateVideos
                )
                
                // Update videos array
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                
                // Update sequence
                videoSequence[index] = newVideo
                
                videos = updatedVideos
                replacingVideoId = nil
                
            } catch {
                self.error = error
                replacingVideoId = nil
            }
        }
    }
    
    func findLeastSimilarVideo(boardVideos: [LikeTheseVideo], candidateVideos: [LikeTheseVideo]) async throws -> LikeTheseVideo {
        // Add retry logic for network and auth issues
        for attempt in 0..<3 {
            do {
                // Check authentication
                guard let currentUser = Auth.auth().currentUser else {
                    print("❌ No authenticated user found (attempt \(attempt + 1))")
                    if attempt == 2 {
                        throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                    continue
                }

                // Ensure we have a fresh token and log it
                let token = try await currentUser.getIDToken()
                print("🎫 Got fresh token (length: \(token.count)) for user: \(currentUser.uid)")
                
                let data: [String: Any] = [
                    "boardVideos": boardVideos.map { [
                        "id": $0.id,
                        "thumbnailUrl": $0.thumbnailUrl ?? ""
                    ]},
                    "candidateVideos": candidateVideos.map { [
                        "id": $0.id,
                        "thumbnailUrl": $0.thumbnailUrl ?? ""
                    ]},
                    "auth": ["token": token]  // Pass token in request data
                ]
                
                print("📤 Calling findLeastSimilarVideo with \(boardVideos.count) board videos and \(candidateVideos.count) candidates")
                let result = try await functions.httpsCallable("findLeastSimilarVideo").call(data)
                print("📥 Received response from findLeastSimilarVideo")
                
                guard let response = result.data as? [String: Any],
                      let chosenId = response["chosen"] as? String else {
                    throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from findLeastSimilarVideo"])
                }
                
                // Store sorted candidates if available
                if let sortedList = response["sortedCandidates"] as? [[String: Any]] {
                    print("📊 Received \(sortedList.count) sorted candidates")
                    // Store for future use if needed
                }
                
                // Find the chosen video in our candidates
                guard let chosen = candidateVideos.first(where: { $0.id == chosenId }) else {
                    print("❌ Chosen video \(chosenId) not found in candidates")
                    throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chosen video not found in candidates"])
                }
                
                print("✅ Found chosen video: \(chosen.id)")
                return chosen
                
            } catch {
                print("❌ Error in findLeastSimilarVideo (attempt \(attempt + 1)): \(error.localizedDescription)")
                if attempt == 2 {
                    throw error
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second before retry
            }
        }
        
        // This should never be reached due to the throw in the loop
        throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to find similar video after retries"])
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
            var replacements: [LikeTheseVideo] = []
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
                        let newBufferVideos = try await withThrowingTaskGroup(of: LikeTheseVideo.self) { group in
                            for _ in 0..<(minBufferSize - videoBuffer.count) {
                                group.addTask {
                                    try await self.firestoreService.fetchRandomVideo()
                                }
                            }
                            
                            var videos: [LikeTheseVideo] = []
                            for try await video in group {
                                videos.append(video)
                            }
                            return videos
                        }
                        
                        await MainActor.run {
                            videoBuffer.append(contentsOf: newBufferVideos)
                        }
                    } catch {
                        print("❌ Error replenishing buffer: \(error.localizedDescription)")
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
    
    func loadVideo(_ video: LikeTheseVideo, boardVideos: [LikeTheseVideo]) {
        self.currentVideo = video
        self.currentBoardVideos = boardVideos
    }
    
    func findLeastSimilarVideo() async throws -> LikeTheseVideo {
        return try await firestoreService.findLeastSimilarVideo(excluding: currentBoardVideos.map { $0.id })
    }
    
    func getNextSortedVideo() async throws -> LikeTheseVideo {
        return try await firestoreService.getNextSortedVideo(currentBoardVideos: currentBoardVideos)
    }
    
    func updateCurrentVideo(_ video: LikeTheseVideo) {
        self.currentVideo = video
    }
    
    func updateBoardVideos(_ videos: [LikeTheseVideo]) {
        self.currentBoardVideos = videos
    }
} 