import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import os
import Network

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "FirestoreService")

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
                self.isNetworkAvailable = path.status == .satisfied
                logger.debug("Network status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
    }
    
    private func handleNetworkError(_ error: Error, attempt: Int) async throws {
        guard attempt < self.maxRetries else {
            logger.error("❌ Max retries reached: \(error.localizedDescription)")
            throw error
        }
        
        if !self.isNetworkAvailable {
            logger.error("❌ Network unavailable, waiting for connection...")
            // Wait for network to become available
            while !self.isNetworkAvailable {
                try await Task.sleep(nanoseconds: self.retryDelay)
            }
        }
        
        logger.debug("🔄 Retrying operation (attempt \(attempt + 1)/\(self.maxRetries))...")
        try await Task.sleep(nanoseconds: self.retryDelay * UInt64(attempt + 1))
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
                return Video(
                    id: document.documentID,
                    url: data["url"] as? String ?? "",
                    thumbnailUrl: data["thumbnailUrl"] as? String,
                    timestamp: (data["timestamp"] as? Timestamp) ?? Timestamp(date: Date())
                )
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
    
    func fetchInitialVideos(limit: Int) async throws -> [Video] {
        logger.debug("📥 Fetching initial \(limit) videos")
        let videosRef = self.db.collection("videos")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        
        let maxRetries = 3
        var currentTry = 0
        var lastError: Error? = nil
        
        while currentTry < maxRetries {
            do {
                logger.debug("🔄 Starting Firestore query (attempt \(currentTry + 1)/\(maxRetries))...")
                let snapshot = try await videosRef.getDocuments()
                logger.debug("✅ Fetched \(snapshot.documents.count) initial videos")
                
                if snapshot.documents.isEmpty {
                    logger.debug("⚠️ No documents found in the videos collection")
                }
                
                // Log each document for debugging
                for doc in snapshot.documents {
                    logger.debug("📄 Document ID: \(doc.documentID), Data: \(doc.data())")
                }
                
                return snapshot.documents.map { document in
                    let data = document.data()
                    logger.debug("🔄 Processing document: \(document.documentID)")
                    return Video(
                        id: document.documentID,
                        url: data["url"] as? String ?? "",
                        thumbnailUrl: data["thumbnailUrl"] as? String,
                        timestamp: (data["timestamp"] as? Timestamp) ?? Timestamp(date: Date())
                    )
                }
            } catch let error as NSError {
                lastError = error
                logger.error("❌ Error fetching videos (attempt \(currentTry + 1)/\(maxRetries)): \(error.localizedDescription)")
                logger.error("❌ Error domain: \(error.domain), code: \(error.code)")
                
                // Only retry on network errors
                if error.domain == NSPOSIXErrorDomain && error.code == 50 {
                    currentTry += 1
                    if currentTry < maxRetries {
                        logger.debug("🔄 Retrying in 1 second...")
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        continue
                    }
                } else {
                    // For non-network errors, throw immediately
                    throw error
                }
            }
            
            currentTry += 1
        }
        
        // If we get here, we've exhausted all retries
        throw lastError ?? NSError(domain: "FirestoreService", code: -1, 
                                 userInfo: [NSLocalizedDescriptionKey: "Failed to fetch videos after \(maxRetries) attempts"])
    }
    
    func fetchMoreVideos(after lastVideoId: String, limit: Int) async throws -> [Video] {
        logger.debug("📥 Fetching \(limit) more videos after \(lastVideoId)")
        let lastVideo = try await db.collection("videos")
            .document(lastVideoId)
            .getDocument()
        
        guard let lastVideoData = lastVideo.data(),
              let timestamp = lastVideoData["timestamp"] as? Timestamp else {
            logger.error("❌ Invalid last video reference")
            throw NSError(domain: "FirestoreService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid last video reference"])
        }
        
        let videosRef = db.collection("videos")
            .order(by: "timestamp", descending: true)
            .start(after: [timestamp])
            .limit(to: limit)
        
        let snapshot = try await videosRef.getDocuments()
        logger.debug("✅ Fetched \(snapshot.documents.count) more videos")
        
        return snapshot.documents.map { document in
            let data = document.data()
            return Video(
                id: document.documentID,
                url: data["url"] as? String ?? "",
                thumbnailUrl: data["thumbnailUrl"] as? String,
                timestamp: (data["timestamp"] as? Timestamp) ?? Timestamp(date: Date())
            )
        }
    }
} 