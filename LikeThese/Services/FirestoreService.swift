import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import os
import Network

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "FirestoreService")

enum FirestoreError: Error {
    case invalidVideoURL(String)
    case emptyVideoCollection
    case invalidVideoData
    case networkError(Error)
    case maxRetriesReached
    
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
        }
    }
}

class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private let maxRetries = 3
    private let retryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    
    private init() {
        logger.debug("🔥 FirestoreService initialized")
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            if let self {
                let oldStatus = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                logger.debug("Network status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
                
                // If network just became available, enable network for Firestore
                if !oldStatus && self.isNetworkAvailable {
                    self.db.enableNetwork { error in
                        if let error = error {
                            logger.error("❌ Failed to enable network: \(error.localizedDescription)")
                        } else {
                            logger.debug("✅ Network enabled for Firestore")
                        }
                    }
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
        
        // Enable offline persistence
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        db.settings = settings
    }
    
    private func handleNetworkError(_ error: Error, attempt: Int) async throws {
        guard attempt < self.maxRetries else {
            logger.error("❌ Max retries reached: \(error.localizedDescription)")
            throw FirestoreError.maxRetriesReached
        }
        
        if !self.isNetworkAvailable {
            logger.error("❌ Network unavailable, waiting for connection...")
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
        
        logger.debug("🔄 Retrying operation (attempt \(attempt + 1)/\(self.maxRetries))...")
        try await Task.sleep(nanoseconds: self.retryDelay * UInt64(attempt + 1))
    }
    
    private func getSignedURL(for path: String) async throws -> URL {
        do {
            logger.debug("🔄 Getting signed URL for path: \(path)")
            let storageRef = storage.reference(withPath: path)
            let signedURLString = try await storageRef.downloadURL()
            logger.debug("✅ Successfully got signed URL: \(signedURLString)")
            return signedURLString
        } catch {
            logger.error("❌ Failed to get signed URL for path \(path): \(error.localizedDescription)")
            throw FirestoreError.networkError(error)
        }
    }
    
    private func validateVideoData(_ data: [String: Any], documentId: String) async throws -> Video {
        logger.debug("🔄 Validating video data for document: \(documentId)")
        logger.debug("📄 Document data: \(data)")
        
        // Get video URL - either from direct URL or storage path
        let videoURL: String
        if let directURL = data["url"] as? String {
            videoURL = directURL
            logger.debug("✅ Using direct video URL")
        } else if let videoFilePath = data["videoFilePath"] as? String {
            videoURL = try await getSignedURL(for: videoFilePath).absoluteString
            logger.debug("✅ Generated signed URL from storage path")
        } else {
            logger.error("❌ No video URL or storage path found in document: \(documentId)")
            throw FirestoreError.invalidVideoData
        }
        
        // Get thumbnail URL - either from direct URL or storage path
        let thumbnailURL: String?
        if let directURL = data["thumbnailUrl"] as? String {
            thumbnailURL = directURL
            logger.debug("✅ Using direct thumbnail URL")
        } else if let thumbnailPath = data["thumbnailFilePath"] as? String {
            do {
                thumbnailURL = try await getSignedURL(for: thumbnailPath).absoluteString
                logger.debug("✅ Generated signed thumbnail URL from storage path")
            } catch {
                logger.error("⚠️ Failed to get thumbnail URL, continuing without thumbnail: \(error.localizedDescription)")
                thumbnailURL = nil
            }
        } else {
            thumbnailURL = nil
            logger.debug("ℹ️ No thumbnail URL or path found")
        }
        
        let video = Video(
            id: documentId,
            url: videoURL,
            thumbnailUrl: thumbnailURL,
            timestamp: (data["timestamp"] as? Timestamp) ?? Timestamp(date: Date())
        )
        
        logger.debug("✅ Successfully validated video data for: \(documentId)")
        return video
    }
    
    private func executeWithRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
        var currentAttempt = 0
        var lastError: Error?
        
        while currentAttempt < maxAttempts {
            do {
                return try await operation()
            } catch let error as NSError {
                lastError = error
                logger.error("❌ Operation failed (attempt \(currentAttempt + 1)/\(maxAttempts)): \(error.localizedDescription)")
                
                // Retry on network errors or Firebase errors
                if error.domain == NSPOSIXErrorDomain || error.domain.contains("Firebase") {
                    currentAttempt += 1
                    if currentAttempt < maxAttempts {
                        logger.debug("🔄 Retrying in 1 second...")
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
    
    func fetchInitialVideos(limit: Int) async throws -> [Video] {
        logger.debug("📥 Fetching initial \(limit) videos")
        
        return try await executeWithRetry { [weak self] in
            guard let self = self else { throw FirestoreError.invalidVideoData }
            
            let videosRef = self.db.collection("videos")
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
            
            let snapshot = try await videosRef.getDocuments()
            logger.debug("✅ Fetched \(snapshot.documents.count) initial videos")
            
            if snapshot.documents.isEmpty {
                throw FirestoreError.emptyVideoCollection
            }
            
            var videos: [Video] = []
            for document in snapshot.documents {
                let data = document.data()
                logger.debug("🔄 Processing document: \(document.documentID)")
                let video = try await validateVideoData(data, documentId: document.documentID)
                videos.append(video)
            }
            return videos
        }
    }
    
    func fetchMoreVideos(after lastVideoId: String, limit: Int) async throws -> [Video] {
        logger.debug("📥 Fetching \(limit) more videos after \(lastVideoId)")
        
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
            logger.debug("✅ Fetched \(snapshot.documents.count) more videos")
            
            if snapshot.documents.isEmpty {
                throw FirestoreError.emptyVideoCollection
            }
            
            var videos: [Video] = []
            for document in snapshot.documents {
                let data = document.data()
                let video = try await validateVideoData(data, documentId: document.documentID)
                videos.append(video)
            }
            return videos
        }
    }
    
    func fetchReplacementVideo(excluding currentVideoId: String) async throws -> Video {
        var currentAttempt = 0
        
        while true {
            do {
                let videosRef = db.collection("videos")
                let query = videosRef
                    .whereField("id", isNotEqualTo: currentVideoId)
                    .limit(to: 1)
                
                let snapshot = try await query.getDocuments()
                
                guard let document = snapshot.documents.first else {
                    throw NSError(domain: "FirestoreService", code: -1, 
                                userInfo: [NSLocalizedDescriptionKey: "No replacement video found"])
                }
                
                let data = document.data()
                return try await validateVideoData(data, documentId: document.documentID)
            } catch {
                try await handleNetworkError(error, attempt: currentAttempt)
                currentAttempt += 1
            }
        }
    }
    
    func recordSkipInteraction(videoId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        logger.debug("📝 Recording skip interaction for video: \(videoId)")
        let interaction = [
            "userId": userId,
            "videoId": videoId,
            "type": "skip",
            "timestamp": FieldValue.serverTimestamp()
        ] as [String : Any]
        
        do {
            try await db.collection("interactions").addDocument(data: interaction)
            logger.debug("✅ Recorded skip interaction")
        } catch {
            logger.error("❌ Error recording skip interaction: \(error.localizedDescription)")
            print("Error recording skip interaction: \(error)")
        }
    }
} 