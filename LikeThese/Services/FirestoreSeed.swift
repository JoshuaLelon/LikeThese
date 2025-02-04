import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Service responsible for seeding the Firestore database with sample data
class FirestoreSeed {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    /// Seeds the database with initial test data
    func seedDatabase() async throws {
        // First seed users
        let users = try await seedUsers()
        
        // Then seed videos
        let videos = try await seedVideos()
        
        // Finally seed some interactions
        try await seedInteractions(users: users, videos: videos)
    }
    
    /// Seeds sample users into Firestore
    private func seedUsers() async throws -> [UserModel] {
        let users = [
            UserModel(
                id: nil,
                name: "Test User 1",
                email: "test1@example.com",
                createdAt: Date(),
                lastLoginAt: Date()
            ),
            UserModel(
                id: nil,
                name: "Test User 2",
                email: "test2@example.com",
                createdAt: Date(),
                lastLoginAt: Date()
            )
        ]
        
        var createdUsers: [UserModel] = []
        for var user in users {
            let docRef = try await db.collection("users").addDocument(from: user)
            user.id = docRef.documentID
            createdUsers.append(user)
        }
        
        return createdUsers
    }
    
    /// Seeds sample videos into Firestore and Storage
    private func seedVideos() async throws -> [VideoModel] {
        // For testing, we'll create video entries that point to placeholder paths
        // In a real app, we'd upload actual video files to Storage
        let videos = [
            VideoModel(
                id: nil,
                videoFilePath: "videos/sample1.mp4",
                thumbnailFilePath: "thumbnails/sample1.jpg",
                createdAt: Date()
            ),
            VideoModel(
                id: nil,
                videoFilePath: "videos/sample2.mp4",
                thumbnailFilePath: "thumbnails/sample2.jpg",
                createdAt: Date()
            ),
            VideoModel(
                id: nil,
                videoFilePath: "videos/sample3.mp4",
                thumbnailFilePath: "thumbnails/sample3.jpg",
                createdAt: Date()
            ),
            VideoModel(
                id: nil,
                videoFilePath: "videos/sample4.mp4",
                thumbnailFilePath: "thumbnails/sample4.jpg",
                createdAt: Date()
            )
        ]
        
        var createdVideos: [VideoModel] = []
        for var video in videos {
            let docRef = try await db.collection("videos").addDocument(from: video)
            video.id = docRef.documentID
            createdVideos.append(video)
        }
        
        return createdVideos
    }
    
    /// Seeds sample interactions into Firestore
    private func seedInteractions(users: [UserModel], videos: [VideoModel]) async throws {
        guard let user = users.first, let userId = user.id else { return }
        
        // Create a video interaction (rewind)
        let videoInteraction = VideoInteractionModel(
            id: nil,
            sourceVideoId: videos[0].id!,
            destinationVideoId: videos[1].id!,
            interactionType: "rewind"
        )
        try await db.collection("interactions").addDocument(from: videoInteraction)
        
        // Create a single swap interaction
        let singleSwap = SingleSwapInteractionModel(
            id: nil,
            sourceVideoId: videos[1].id!,
            destinationVideoId: videos[2].id!,
            position: .topLeft
        )
        try await db.collection("interactions").addDocument(from: singleSwap)
        
        // Create a double swap interaction
        let doubleSwap = DoubleSwapInteractionModel(
            id: nil,
            sourceVideoId1: videos[0].id!,
            destinationVideoId1: videos[2].id!,
            sourceVideoId2: videos[1].id!,
            destinationVideoId2: videos[3].id!,
            swapType: .topTwo
        )
        try await db.collection("interactions").addDocument(from: doubleSwap)
        
        // Create a quadruple swap interaction
        let quadSwap = QuadrupleSwapInteractionModel(
            id: nil,
            sourceVideoId1: videos[0].id!,
            destinationVideoId1: videos[2].id!,
            sourceVideoId2: videos[1].id!,
            destinationVideoId2: videos[3].id!,
            sourceVideoId3: videos[2].id!,
            destinationVideoId3: videos[0].id!,
            sourceVideoId4: videos[3].id!,
            destinationVideoId4: videos[1].id!
        )
        try await db.collection("interactions").addDocument(from: quadSwap)
    }
} 