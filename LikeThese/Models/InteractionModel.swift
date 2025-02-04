import Foundation
import FirebaseFirestore

struct InteractionModel: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let videoId: String
    let type: InteractionType
    let createdAt: Date
    
    enum InteractionType: String, Codable {
        case view
        case swipeUp
        case swipeDown
        case swipeLeft
        case swipeRight
        case multiswipe
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case videoId = "video_id"
        case type
        case createdAt = "created_at"
    }
} 