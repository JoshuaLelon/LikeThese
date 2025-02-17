import Foundation
import FirebaseFirestore

struct UserModel: Codable, Identifiable {
    @DocumentID var id: String?
    let name: String
    let email: String
    let createdAt: Date
    var lastLoginAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case createdAt = "created_at"
        case lastLoginAt = "last_login_at"
    }
} 