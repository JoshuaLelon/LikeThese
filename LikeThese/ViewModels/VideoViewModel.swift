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
    
    private var sortedCandidates: [(videoId: String, distance: Double)] = []
    private var nextVideoIndex: Int = 0
    
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
            // Fetch 4 random videos for initial grid
            var initialVideos: [LikeTheseVideo] = []
            for _ in 0..<4 {
                let video = try await firestoreService.fetchRandomVideo()
                initialVideos.append(video)
            }
            print("✅ Loaded \(initialVideos.count) initial videos")
            
            // Fetch buffer videos in parallel
            let bufferVideos = try await withThrowingTaskGroup(of: LikeTheseVideo.self) { group in
                for _ in 0..<minBufferSize {
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
            
            videoBuffer = bufferVideos
            
            // Store initial sequence
            for (index, video) in initialVideos.enumerated() {
                videoSequence[index] = video
            }
            
            videos = initialVideos
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
                        if !videos.contains(where: { $0.id == video.id }) {
                            candidateVideos.append(video)
                        }
                    } catch {
                        print("❌ Error fetching candidate video: \(error.localizedDescription)")
                    }
                }
                
                // Make sure we have at least one candidate
                guard !candidateVideos.isEmpty else {
                    throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No candidate videos available"])
                }
                
                // Find least similar video using AI and create sorted queue
                let newVideo = try await findLeastSimilarVideo(
                    boardVideos: boardVideos,
                    candidateVideos: candidateVideos
                )
                
                // Create new sorted queue since grid state is changing
                print("🔄 QUEUE: Grid state changing, creating new sorted queue")
                try await createSortedQueue(from: newVideo, boardVideos: boardVideos)
                print("✅ Created new sorted queue due to grid state change")
                
                // Update videos array atomically
                await MainActor.run {
                    var updatedVideos = videos
                    if let removeIndex = updatedVideos.firstIndex(where: { $0.id == videoId }) {
                        updatedVideos.remove(at: removeIndex)
                        updatedVideos.insert(newVideo, at: removeIndex)
                        
                        // Update sequence
                        videoSequence[removeIndex] = newVideo
                        
                        videos = updatedVideos
                    }
                    replacingVideoId = nil
                }
                
            } catch {
                await MainActor.run {
                    self.error = error
                    replacingVideoId = nil
                }
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
                
                // Get all videos except those on the board for candidates
                let allCandidates = try await firestoreService.fetchVideos()
                let filteredCandidates = allCandidates.filter { candidate in
                    !boardVideos.contains { $0.id == candidate.id }
                }
                
                let data: [String: Any] = [
                    "boardVideos": boardVideos.map { [
                        "id": $0.id,
                        "thumbnailUrl": $0.thumbnailUrl ?? "",
                        "frameUrl": $0.frameUrl ?? $0.thumbnailUrl ?? ""
                    ]},
                    "candidateVideos": filteredCandidates.map { [
                        "id": $0.id,
                        "thumbnailUrl": $0.thumbnailUrl ?? "",
                        "frameUrl": $0.frameUrl ?? $0.thumbnailUrl ?? ""
                    ]},
                    "auth": ["token": token]
                ]
                
                print("📤 Calling findLeastSimilarVideo with \(boardVideos.count) board videos and \(filteredCandidates.count) candidates")
                let result = try await functions.httpsCallable("findLeastSimilarVideo").call(data)
                print("📥 Received response from findLeastSimilarVideo")
                
                guard let response = result.data as? [String: Any],
                      let chosenId = response["chosen"] as? String else {
                    throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from findLeastSimilarVideo"])
                }
                
                // Store sorted candidates if available
                if let sortedList = response["sortedCandidates"] as? [[String: Any]] {
                    print("📊 Received \(sortedList.count) sorted candidates")
                    self.sortedCandidates = sortedList.compactMap { candidate in
                        guard let videoId = candidate["videoId"] as? String,
                              let distance = candidate["distance"] as? Double else {
                            return nil
                        }
                        return (videoId: videoId, distance: distance)
                    }
                    self.nextVideoIndex = 0
                }
                
                // Find the chosen video in our candidates
                guard let chosen = filteredCandidates.first(where: { $0.id == chosenId }) else {
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
        print("📥 QUEUE: Loading video \(video.id)")
        print("📊 QUEUE: Board videos count: \(boardVideos.count)")
        self.currentVideo = video
        self.currentBoardVideos = boardVideos
        
        debugQueueState()
    }
    
    func findLeastSimilarVideo() async throws -> LikeTheseVideo {
        return try await firestoreService.findLeastSimilarVideo(excluding: currentBoardVideos.map { $0.id })
    }
    
    func createSortedQueue(from currentVideo: LikeTheseVideo, boardVideos: [LikeTheseVideo]) async throws {
        print("🔄 QUEUE: Creating new queue from \(currentVideo.id) with \(boardVideos.count) board videos")

        guard let currentUser = Auth.auth().currentUser else {
            print("❌ QUEUE: No authenticated user")
            throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }

        let token = try await currentUser.getIDToken(forcingRefresh: true)
        
        let allCandidates = try await firestoreService.fetchVideos()
        print("📊 QUEUE Stats:")
        print("  - Total/Board/Expected: \(allCandidates.count)/\(boardVideos.count)/\(allCandidates.count - boardVideos.count)")
        
        let filteredCandidates = allCandidates.filter { candidate in
            !boardVideos.contains { $0.id == candidate.id }
        }
        
        if filteredCandidates.count != allCandidates.count - boardVideos.count {
            print("⚠️ QUEUE: Size mismatch! Missing \(allCandidates.count - boardVideos.count - filteredCandidates.count) videos")
        }

        let data: [String: Any] = [
            "boardVideos": boardVideos.map { [
                "id": $0.id,
                "thumbnailUrl": $0.thumbnailUrl ?? "",
                "frameUrl": $0.frameUrl ?? $0.thumbnailUrl ?? ""
            ]},
            "candidateVideos": filteredCandidates.map { [
                "id": $0.id,
                "thumbnailUrl": $0.thumbnailUrl ?? "",
                "frameUrl": $0.frameUrl ?? $0.thumbnailUrl ?? ""
            ]},
            "auth": ["token": token]
        ]
        
        print("📤 Creating sorted queue with \(boardVideos.count) board and \(filteredCandidates.count) candidate videos")
        let result = try await functions.httpsCallable("findLeastSimilarVideo").call(data)
        
        guard let response = result.data as? [String: Any],
              let sortedList = response["sortedCandidates"] as? [[String: Any]] else {
            throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response when creating sorted queue"])
        }
        
        self.sortedCandidates = sortedList.compactMap { candidate in
            guard let videoId = candidate["videoId"] as? String,
                  let distance = candidate["distance"] as? Double else {
                print("⚠️ QUEUE: Invalid candidate format")
                return nil
            }
            return (videoId: videoId, distance: distance)
        }
        print("📊 QUEUE: Created queue with \(self.sortedCandidates.count) videos")
        self.nextVideoIndex = 0
        
        // Preload next video if available
        if !self.sortedCandidates.isEmpty {
            Task {
                do {
                    let nextVideo = try await firestoreService.fetchVideoById(self.sortedCandidates[0].videoId)
                    print("🔄 Preloaded next video: \(nextVideo.id)")
                } catch {
                    print("⚠️ Failed to preload next video: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func getNextSortedVideo() async throws -> LikeTheseVideo {
        print("🔄 QUEUE: Next video request (index: \(nextVideoIndex)/\(sortedCandidates.count))")
        
        // If queue is empty or we've reached the end, try to refresh it
        if sortedCandidates.isEmpty || nextVideoIndex >= sortedCandidates.count {
            print("🔄 QUEUE: Refreshing empty or completed queue")
            guard let currentVideo = currentVideo, !currentBoardVideos.isEmpty else {
                throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current video or board videos available"])
            }
            
            try await createSortedQueue(from: currentVideo, boardVideos: currentBoardVideos)
            
            // If still empty after refresh, throw error
            guard !sortedCandidates.isEmpty else {
                print("❌ QUEUE: Queue still empty after refresh")
                throw NSError(domain: "VideoViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No sorted queue available after refresh"])
            }
        }
        
        let nextCandidate = sortedCandidates[nextVideoIndex]
        let video = try await firestoreService.fetchVideoById(nextCandidate.videoId)
        
        nextVideoIndex += 1
        print("✅ QUEUE: Got video \(video.id) (\(sortedCandidates.count - nextVideoIndex) remaining)")
        
        return video
    }
    
    func updateCurrentVideo(_ video: LikeTheseVideo) {
        self.currentVideo = video
    }
    
    func updateBoardVideos(_ videos: [LikeTheseVideo]) {
        self.currentBoardVideos = videos
    }
    
    // Add helper function to debug queue state
    func debugQueueState() {
        print("\n📊 QUEUE STATE:")
        print("  - Size/Index: \(sortedCandidates.count)/\(nextVideoIndex)")
        print("  - Board videos: \(currentBoardVideos.count)")
        if !sortedCandidates.isEmpty {
            let nextIds = sortedCandidates.dropFirst(nextVideoIndex).prefix(3).map { $0.videoId }
            print("  - Next up: \(nextIds.joined(separator: ", "))")
        }
        print("")
    }
} 