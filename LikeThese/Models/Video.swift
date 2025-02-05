import Foundation
import FirebaseFirestore

struct Video: Identifiable {
    let id: String
    let url: String
    let thumbnailUrl: String?
    let timestamp: Timestamp
    
    init(id: String, url: String, thumbnailUrl: String? = nil, timestamp: Timestamp) {
        self.id = id
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.timestamp = timestamp
    }
} 