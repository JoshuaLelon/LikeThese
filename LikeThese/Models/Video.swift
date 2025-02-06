import Foundation
import FirebaseFirestore

struct Video: Identifiable, Equatable {
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
    
    static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id
    }
} 