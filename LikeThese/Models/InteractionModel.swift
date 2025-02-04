import Foundation
import FirebaseFirestore

/// Base model for all interactions. Contains common fields shared by all interaction types.
struct InteractionModel: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case timestamp
    }
}

/// Represents a basic video interaction where a user moves from one video to another.
/// Used for simple navigation actions like rewinding to a previous video or skipping to the next.
struct VideoInteractionModel: Codable, Identifiable {
    @DocumentID var id: String?
    let sourceVideoId: String
    let destinationVideoId: String
    let interactionType: String // "rewind" or "skip"
    
    enum CodingKeys: String, CodingKey {
        case id
        case sourceVideoId = "source_video_id"
        case destinationVideoId = "destination_video_id"
        case interactionType = "interaction_type"
    }
}

/// Represents a single video swap in the 2x2 grid.
/// Used when a user swaps out one video in a specific position of the grid.
struct SingleSwapInteractionModel: Codable, Identifiable {
    @DocumentID var id: String?
    let sourceVideoId: String
    let destinationVideoId: String
    let position: SwapPosition
    
    /// Defines the possible positions in the 2x2 grid where a video can be swapped
    enum SwapPosition: String, Codable {
        case topLeft = "topLeft"
        case bottomLeft = "bottomLeft"
        case topRight = "topRight"
        case bottomRight = "bottomRight"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case sourceVideoId = "source_video_id"
        case destinationVideoId = "destination_video_id"
        case position
    }
}

/// Represents a double video swap in the 2x2 grid.
/// Used when a user swaps out two adjacent videos simultaneously (top two, bottom two, left two, or right two).
struct DoubleSwapInteractionModel: Codable, Identifiable {
    @DocumentID var id: String?
    let sourceVideoId1: String
    let destinationVideoId1: String
    let sourceVideoId2: String
    let destinationVideoId2: String
    let swapType: SwapType
    
    /// Defines the possible pairs of positions that can be swapped together
    enum SwapType: String, Codable {
        case topTwo = "topTwo"       // Swaps both videos in the top row
        case bottomTwo = "bottomTwo" // Swaps both videos in the bottom row
        case leftTwo = "leftTwo"     // Swaps both videos in the left column
        case rightTwo = "rightTwo"   // Swaps both videos in the right column
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case sourceVideoId1 = "source_video_id_1"
        case destinationVideoId1 = "destination_video_id_1"
        case sourceVideoId2 = "source_video_id_2"
        case destinationVideoId2 = "destination_video_id_2"
        case swapType = "swap_type"
    }
}

/// Represents a complete grid swap where all four videos are replaced simultaneously.
/// Used when a user chooses to refresh their entire inspiration board at once.
struct QuadrupleSwapInteractionModel: Codable, Identifiable {
    @DocumentID var id: String?
    let sourceVideoId1: String
    let destinationVideoId1: String
    let sourceVideoId2: String
    let destinationVideoId2: String
    let sourceVideoId3: String
    let destinationVideoId3: String
    let sourceVideoId4: String
    let destinationVideoId4: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case sourceVideoId1 = "source_video_id_1"
        case destinationVideoId1 = "destination_video_id_1"
        case sourceVideoId2 = "source_video_id_2"
        case destinationVideoId2 = "destination_video_id_2"
        case sourceVideoId3 = "source_video_id_3"
        case destinationVideoId3 = "destination_video_id_3"
        case sourceVideoId4 = "source_video_id_4"
        case destinationVideoId4 = "destination_video_id_4"
    }
} 