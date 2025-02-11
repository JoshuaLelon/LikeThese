import Foundation
import FirebaseFirestore

// Make the type accessible from other modules
public struct LikeTheseVideo: Identifiable, Codable, Equatable {
    public let id: String
    public let url: String
    public let thumbnailUrl: String
    public var frameUrl: String?
    public let timestamp: Timestamp
    
    public init(id: String, url: String, thumbnailUrl: String, frameUrl: String? = nil, timestamp: Timestamp) {
        self.id = id
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.frameUrl = frameUrl
        self.timestamp = timestamp
    }
    
    public static func == (lhs: LikeTheseVideo, rhs: LikeTheseVideo) -> Bool {
        lhs.id == rhs.id
    }
    
    // Add Codable conformance for Timestamp
    private enum CodingKeys: String, CodingKey {
        case id, url, thumbnailUrl, frameUrl, timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        thumbnailUrl = try container.decode(String.self, forKey: .thumbnailUrl)
        frameUrl = try container.decodeIfPresent(String.self, forKey: .frameUrl)
        timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encodeIfPresent(frameUrl, forKey: .frameUrl)
        try container.encode(timestamp, forKey: .timestamp)
    }
} 