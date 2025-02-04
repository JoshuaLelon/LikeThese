import Foundation
import FirebaseFirestore

struct VideoModel: Codable, Identifiable {
    @DocumentID var id: String?
    let title: String
    let description: String?
    let videoUrl: String
    let thumbnailUrl: String?
    let createdAt: Date
    var viewCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case createdAt = "created_at"
        case viewCount = "view_count"
    }
} 