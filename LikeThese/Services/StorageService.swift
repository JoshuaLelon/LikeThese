import Foundation
import FirebaseStorage

class StorageService {
    private let storage = Storage.storage()
    
    func fetchRandomVideo() async throws -> URL {
        let storageRef = storage.reference().child("videos")
        
        // List all items in videos directory
        let result = try await storageRef.listAll()
        
        // Get a random video from the list
        guard let randomItem = result.items.randomElement() else {
            throw NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No videos found"])
        }
        
        // Get download URL
        return try await randomItem.downloadURL()
    }
} 