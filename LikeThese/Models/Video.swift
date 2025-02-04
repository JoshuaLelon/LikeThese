import Foundation
import FirebaseFirestore

struct Video: Codable, Identifiable {
    let id: String
    let url: String
    let thumbnailUrl: String?
    let timestamp: Timestamp
    
    enum CodingKeys: String, CodingKey {
        case id
        case url
        case thumbnailUrl
        case timestamp
    }
} 