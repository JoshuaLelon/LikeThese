import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import Network

enum FirestoreError: Error {
    case invalidVideoURL(String)
    case emptyVideoCollection
    case invalidVideoData
    case networkError(Error)
    case maxRetriesReached
    case documentNotFound(String)
    case videoNotFound
    
    var localizedDescription: String {
        switch self {
        case .invalidVideoURL(let url):
            return "Invalid video URL: \(url)"
        case .emptyVideoCollection:
            return "No videos found in collection"
        case .invalidVideoData:
            return "Invalid video data in document"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .maxRetriesReached:
            return "Failed after maximum retry attempts"
        case .documentNotFound(let id):
            return "Document not found: \(id)"
        case .videoNotFound:
            return "Video not found"
        }
    }
}

class FirestoreService: ObservableObject {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private let maxRetries = 3
    private let retryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    
    @Published private(set) var videos: [LikeTheseVideo] = []
    
    private init() {
        print("🔥 FirestoreService initialized")
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            if let self {
                let oldStatus = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                print("Network status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
                
                // If network just became available, enable network for Firestore
                if !oldStatus && self.isNetworkAvailable {
                    self.db.enableNetwork { error in
                        if let error = error {
                            print("❌ Failed to enable network: \(error.localizedDescription)")
                        } else {
                            print("✅ Network enabled for Firestore")
                        }
                    }
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
        
        // Enable offline persistence with default settings
        let settings = FirestoreSettings()
        db.settings = settings
    }
    
    private func handleNetworkError(_ error: Error, attempt: Int) async throws {
        guard attempt < self.maxRetries else {
            print("❌ Max retries reached: \(error.localizedDescription)")
            throw FirestoreError.maxRetriesReached
        }
        
        if !self.isNetworkAvailable {
            print("❌ Network unavailable, waiting for connection...")
            // Wait for network to become available
            while !self.isNetworkAvailable {
                try await Task.sleep(nanoseconds: self.retryDelay)
            }
            
            // Re-enable network for Firestore when connection is restored
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.db.enableNetwork { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
        
        print("🔄 Retrying operation (attempt \(attempt + 1)/\(self.maxRetries))...")
        try await Task.sleep(nanoseconds: self.retryDelay * UInt64(attempt + 1))
    }
    
    private func getSignedURL(for path: String) async throws -> URL {
        do {
            print("🔄 Getting signed URL for path: \(path)")
            let storageRef = storage.reference(withPath: path)
            let signedURLString = try await storageRef.downloadURL()
            print("✅ Successfully got signed URL: \(signedURLString)")
            return signedURLString
        } catch {
            print("❌ Failed to get signed URL for path \(path): \(error.localizedDescription)")
            throw FirestoreError.networkError(error)
        }
    }
    
    private func validateVideoData(_ data: [String: Any], documentId: String) async throws -> LikeTheseVideo {
        print("🔄 Validating video data for document: \(documentId)")
        print("📄 Document data: \(data)")
        
        // First try to use signed URLs if available
        if let signedVideoUrl = data["signedVideoUrl"] as? String,
           let signedThumbnailUrl = data["signedThumbnailUrl"] as? String {
            print("✅ Using pre-signed URLs")
            let video = LikeTheseVideo(
                id: documentId,
                url: signedVideoUrl,
                thumbnailUrl: signedThumbnailUrl,
                timestamp: (data["timestamp"] as? Timestamp) ?? Timestamp(date: Date())
            )
            print("📄 Video URL: \(signedVideoUrl)")
            print("📄 Thumbnail URL: \(signedThumbnailUrl)")
            return video
        }
        
        // Fallback to generating signed URLs from paths
        if let videoPath = data["videoPath"] as? String {
            let videoURL = try await getSignedURL(for: videoPath).absoluteString
            let thumbnailPath = data["thumbnailPath"] as? String ?? videoPath
            let thumbnailURL = try await getSignedURL(for: thumbnailPath).absoluteString
            
            let video = LikeTheseVideo(
                id: documentId,
                url: videoURL,
                thumbnailUrl: thumbnailURL,
                timestamp: (data["timestamp"] as? Timestamp) ?? Timestamp(date: Date())
            )
            print("✅ Generated new signed URLs from paths")
            print("📄 Video URL: \(videoURL)")
            print("📄 Thumbnail URL: \(thumbnailURL)")
            return video
        }
        
        // Legacy fallback for old documents
        let videoURL: String
        if let url = data["url"] as? String {
            // Convert storage URL to storage path
            if url.contains("storage.googleapis.com") {
                let components = url.components(separatedBy: "/videos/")
                if let filename = components.last {
                    let storagePath = "videos/\(filename)"
                    videoURL = try await getSignedURL(for: storagePath).absoluteString
                    print("✅ Generated signed URL from storage URL")
                } else {
                    print("❌ Invalid video URL format: \(url)")
                    throw FirestoreError.invalidVideoURL(url)
                }
            } else {
                videoURL = url
                print("✅ Using direct video URL")
            }
        } else if let videoFilePath = data["videoFilePath"] as? String {
            videoURL = try await getSignedURL(for: videoFilePath).absoluteString
            print("✅ Generated signed URL from storage path")
        } else {
            print("❌ No video URL or storage path found in document: \(documentId)")
            throw FirestoreError.invalidVideoData
        }
        
        // Get thumbnail URL - either from direct URL or storage path
        let thumbnailURL: String
        if let url = data["thumbnailUrl"] as? String {
            // Convert storage URL to storage path
            if url.contains("storage.googleapis.com") {
                let components = url.components(separatedBy: "/thumbnails/")
                if let filename = components.last {
                    let storagePath = "thumbnails/\(filename)"
                    thumbnailURL = try await getSignedURL(for: storagePath).absoluteString
                    print("✅ Generated signed thumbnail URL from storage URL")
                } else {
                    print("⚠️ Invalid thumbnail URL format: \(url), using video URL")
                    thumbnailURL = videoURL
                }
            } else {
                thumbnailURL = url
                print("✅ Using direct thumbnail URL")
            }
        } else if let thumbnailPath = data["thumbnailFilePath"] as? String {
            do {
                thumbnailURL = try await getSignedURL(for: thumbnailPath).absoluteString
                print("✅ Generated signed thumbnail URL from storage path")
            } catch {
                print("⚠️ Failed to get thumbnail URL, using video URL: \(error.localizedDescription)")
                thumbnailURL = videoURL
            }
        } else {
            thumbnailURL = videoURL
            print("ℹ️ No thumbnail URL or path found, using video URL")
        }
        
        print("✅ Successfully validated video data for: \(documentId)")
        print("📄 Video URL: \(videoURL)")
        print("📄 Thumbnail URL: \(thumbnailURL)")
        
        let video = LikeTheseVideo(
            id: documentId,
            url: videoURL,
            thumbnailUrl: thumbnailURL,
            timestamp: (data["timestamp"] as? Timestamp) ?? Timestamp(date: Date())
        )
        
        return video
    }
    
    private func executeWithRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
        var currentAttempt = 0
        
        while currentAttempt < maxAttempts {
            do {
                return try await operation()
            } catch let error as NSError {
                print("❌ Operation failed (attempt \(currentAttempt + 1)/\(maxAttempts)): \(error.localizedDescription)")
                
                // Retry on network errors or Firebase errors
                if error.domain == NSPOSIXErrorDomain || error.domain.contains("Firebase") {
                    currentAttempt += 1
                    if currentAttempt < maxAttempts {
                        print("🔄 Retrying in 1 second...")
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        continue
                    }
                } else {
                    // For other errors, throw immediately
                    throw error
                }
            }
        }
        
        throw FirestoreError.maxRetriesReached
    }
    
    func fetchInitialVideos(limit: Int) async throws -> [LikeTheseVideo] {
        print("📥 Fetching initial \(limit) videos")
        
        return try await executeWithRetry { [weak self] in
            guard let self = self else { throw FirestoreError.invalidVideoData }
            
            let videosRef = self.db.collection("videos")
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
            
            let snapshot = try await videosRef.getDocuments()
            print("✅ Fetched \(snapshot.documents.count) initial videos")
            
            if snapshot.documents.isEmpty {
                throw FirestoreError.emptyVideoCollection
            }
            
            var videos: [LikeTheseVideo] = []
            for document in snapshot.documents {
                let data = document.data()
                print("🔄 Processing document: \(document.documentID)")
                let video = try await validateVideoData(data, documentId: document.documentID)
                videos.append(video)
            }
            
            // If we don't have enough videos, replicate existing ones
            if videos.count < limit {
                print("⚠️ Not enough videos, replicating existing ones")
                while videos.count < limit {
                    // Take a random video from the existing ones and create a copy
                    if let originalVideo = videos.randomElement() {
                        let replicatedVideo = LikeTheseVideo(
                            id: "\(originalVideo.id)_replica_\(UUID().uuidString)",
                            url: originalVideo.url,
                            thumbnailUrl: originalVideo.thumbnailUrl,
                            timestamp: Timestamp(date: Date())
                        )
                        videos.append(replicatedVideo)
                    }
                }
            }
            
            return videos
        }
    }
    
    func fetchMoreVideos(after lastVideoId: String, limit: Int) async throws -> [LikeTheseVideo] {
        print("📥 Fetching \(limit) more videos after \(lastVideoId)")
        
        return try await executeWithRetry { [weak self] in
            guard let self = self else { throw FirestoreError.invalidVideoData }
            
            let lastVideo = try await self.db.collection("videos")
                .document(lastVideoId)
                .getDocument()
            
            guard let lastVideoData = lastVideo.data(),
                  let timestamp = lastVideoData["timestamp"] as? Timestamp else {
                throw FirestoreError.invalidVideoData
            }
            
            let videosRef = self.db.collection("videos")
                .order(by: "timestamp", descending: true)
                .start(after: [timestamp])
                .limit(to: limit)
            
            let snapshot = try await videosRef.getDocuments()
            print("✅ Fetched \(snapshot.documents.count) more videos")
            
            if snapshot.documents.isEmpty {
                throw FirestoreError.emptyVideoCollection
            }
            
            var videos: [LikeTheseVideo] = []
            for document in snapshot.documents {
                let data = document.data()
                let video = try await validateVideoData(data, documentId: document.documentID)
                videos.append(video)
            }
            return videos
        }
    }
    
    func fetchReplacementVideo(excluding currentVideoId: String) async throws -> LikeTheseVideo {
        print("🔄 Fetching replacement video excluding: \(currentVideoId)")
        
        // Check auth state
        guard Auth.auth().currentUser != nil else {
            print("❌ User not authenticated")
            throw FirestoreError.networkError(NSError(domain: "FirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
        }
        
        // Check network state
        guard isNetworkAvailable else {
            print("❌ Network unavailable")
            throw FirestoreError.networkError(NSError(domain: "FirestoreService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Network unavailable"]))
        }
        
        // First get all videos ordered by timestamp
        let videosRef = db.collection("videos")
            .order(by: "timestamp", descending: true)
            .limit(to: 10)  // Limit to avoid loading too many
        
        do {
            let snapshot = try await videosRef.getDocuments()
            // Filter out the current video client-side
            let filteredDocs = snapshot.documents.filter { $0.documentID != currentVideoId }
            
            guard let document = filteredDocs.first else {
                print("❌ No replacement video found")
                throw FirestoreError.emptyVideoCollection
            }
            
            let data = document.data()
            return try await validateVideoData(data, documentId: document.documentID)
        } catch let error as NSError {
            print("❌ Error fetching replacement video: \(error.localizedDescription)")
            if error.domain.contains("Firebase") || error.domain == NSPOSIXErrorDomain {
                throw FirestoreError.networkError(error)
            }
            throw error
        }
    }
    
    func recordSkipInteraction(videoId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("📝 Recording skip interaction for video: \(videoId)")
        let interaction = [
            "userId": userId,
            "videoId": videoId,
            "type": "skip",
            "timestamp": FieldValue.serverTimestamp()
        ] as [String : Any]
        
        do {
            try await db.collection("interactions").addDocument(data: interaction)
            print("✅ Recorded skip interaction")
        } catch {
            print("❌ Error recording skip interaction: \(error.localizedDescription)")
            print("Error recording skip interaction: \(error)")
        }
    }
    
    // MARK: - Autoplay functionality for Phase 7
    func fetchNextRecommendedVideo(completion: @escaping (URL?) -> Void) {
        db.collection("videos")
          .order(by: "timestamp", descending: true)
          .limit(to: 1)
          .getDocuments { snapshot, error in
              if let error = error {
                  print("Error fetching next video: \(error.localizedDescription)")
                  completion(nil)
                  return
              }
              guard let document = snapshot?.documents.first,
                    let data = document.data()["videoUrl"] as? String,
                    let videoURL = URL(string: data) else {
                  print("No more videos found.")
                  completion(nil)
                  return
              }
              print("Autoplaying next video: \(document.documentID)")
              completion(videoURL)
          }
    }
    
    func fetchRandomVideo() async throws -> LikeTheseVideo {
        print("🎲 Fetching random video")
        
        return try await executeWithRetry { [weak self] in
            guard let self = self else { throw FirestoreError.invalidVideoData }
            
            // Get a random video from the collection
            let videosRef = self.db.collection("videos")
            let snapshot = try await videosRef.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                throw FirestoreError.emptyVideoCollection
            }
            
            // Get a random document
            let randomDoc = snapshot.documents.randomElement()!
            let data = randomDoc.data()
            
            print("🎲 Selected random video: \(randomDoc.documentID)")
            let video = try await validateVideoData(data, documentId: randomDoc.documentID)
            
            // If this is a replica request and we're running low on videos,
            // create a replica instead of fetching a new one
            if snapshot.documents.count < 4 {
                print("⚠️ Low on videos, creating replica")
                return LikeTheseVideo(
                    id: "\(video.id)_replica_\(UUID().uuidString)",
                    url: video.url,
                    thumbnailUrl: video.thumbnailUrl,
                    timestamp: Timestamp(date: Date())
                )
            }
            
            return video
        }
    }
    
    func fetchVideos() async throws -> [LikeTheseVideo] {
        let snapshot = try await db.collection("videos").getDocuments()
        return try await withThrowingTaskGroup(of: LikeTheseVideo.self) { group in
            var videos: [LikeTheseVideo] = []
            for document in snapshot.documents {
                group.addTask {
                    try await self.validateVideoData(document.data(), documentId: document.documentID)
                }
            }
            for try await video in group {
                videos.append(video)
            }
            return videos
        }
    }
    
    func getVideo(id: String) async throws -> LikeTheseVideo {
        let document = try await db.collection("videos").document(id).getDocument()
        guard document.exists else {
            throw FirestoreError.documentNotFound(id)
        }
        return try await validateVideoData(document.data() ?? [:], documentId: document.documentID)
    }
    
    func addVideo(_ video: LikeTheseVideo) async throws {
        try await db.collection("videos").document(video.id).setData([
            "url": video.url,
            "thumbnailUrl": video.thumbnailUrl,
            "frameUrl": video.frameUrl as Any,
            "timestamp": video.timestamp
        ])
    }
    
    func updateVideo(_ video: LikeTheseVideo) async throws {
        try await db.collection("videos").document(video.id).updateData([
            "url": video.url,
            "thumbnailUrl": video.thumbnailUrl,
            "frameUrl": video.frameUrl as Any,
            "timestamp": video.timestamp
        ])
    }
    
    func deleteVideo(_ video: LikeTheseVideo) async throws {
        try await db.collection("videos").document(video.id).delete()
    }
    
    func findLeastSimilarVideo(excluding videoIds: [String]) async throws -> LikeTheseVideo {
        print("🔄 Finding least similar video excluding \(videoIds.count) videos")
        
        // Get all videos except excluded ones
        let snapshot = try await db.collection("videos")
            .whereField("id", notIn: videoIds)
            .getDocuments()
        
        guard !snapshot.documents.isEmpty else {
            throw FirestoreError.emptyVideoCollection
        }
        
        // Get a random video from the remaining ones
        let randomDoc = snapshot.documents.randomElement()!
        let data = randomDoc.data()
        
        return try await validateVideoData(data, documentId: randomDoc.documentID)
    }
    
    func getNextSortedVideo(currentBoardVideos: [LikeTheseVideo]) async throws -> LikeTheseVideo {
        print("🔄 Getting next sorted video")
        
        // For now, just get a random video that's not in the current board
        let excludedIds = currentBoardVideos.map { $0.id }
        return try await findLeastSimilarVideo(excluding: excludedIds)
    }
    
    func fetchVideoById(_ videoId: String) async throws -> LikeTheseVideo {
        print("🔍 Fetching video by ID: \(videoId)")
        let snapshot = try await db.collection("videos")
            .whereField("id", isEqualTo: videoId)
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            throw FirestoreError.videoNotFound
        }
        
        return try await validateVideoData(document.data(), documentId: document.documentID)
    }
} 