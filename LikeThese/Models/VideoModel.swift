import Foundation
import FirebaseFirestore

struct VideoModel: Codable, Identifiable {
    @DocumentID var id: String?
    let videoFilePath: String
    let thumbnailFilePath: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case videoFilePath = "video_file_path"
        case thumbnailFilePath = "thumbnail_file_path"
        case createdAt = "created_at"
    }
} 