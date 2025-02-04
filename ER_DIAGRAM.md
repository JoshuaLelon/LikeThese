# ER Diagram
```
erDiagram
    USER {
        string userId
        string name
        string email
    }

    VIDEO {
        string videoId
        string videoFilePath "Firebase Storage path for video"
        string thumbnailFilePath "Firebase Storage path for thumbnail image"
    }

    INTERACTION {
        string interactionId
        string userId
        datetime timestamp
    }

    %% Parent for video interactions
    VIDEO_INTERACTION {
        string videoInteractionId
        string sourceVideoId
        string destinationVideoId
        string interactionType "rewind or skip"
    }

    %% Subtypes of swap interactions
    SINGLE_SWAP_INTERACTION {
        string singleSwapInteractionId
        string sourceVideoId
        string destinationVideoId
        string position "topLeft, bottomLeft, topRight, bottomRight"
    }

    DOUBLE_SWAP_INTERACTION {
        string doubleSwapInteractionId
        string sourceVideoId1
        string destinationVideoId1
        string sourceVideoId2
        string destinationVideoId2
        string swapType "topTwo, bottomTwo, leftTwo, rightTwo"
    }

    QUADRUPLE_SWAP_INTERACTION {
        string quadrupleSwapInteractionId
        string sourceVideoId1
        string destinationVideoId1
        string sourceVideoId2
        string destinationVideoId2
        string sourceVideoId3
        string destinationVideoId3
        string sourceVideoId4
        string destinationVideoId4
    }

    %% Relationships
    USER ||--o{ INTERACTION : "records"
    INTERACTION ||--o{ VIDEO_INTERACTION : "specializes"
    INTERACTION ||--o{ SINGLE_SWAP_INTERACTION : "specializes"
    INTERACTION ||--o{ DOUBLE_SWAP_INTERACTION : "specializes"
    INTERACTION ||--o{ QUADRUPLE_SWAP_INTERACTION : "specializes"
    VIDEO ||--o{ VIDEO_INTERACTION : "involves"
    VIDEO ||--o{ SINGLE_SWAP_INTERACTION : "replaces"
    VIDEO ||--o{ DOUBLE_SWAP_INTERACTION : "replaces"
    VIDEO ||--o{ QUADRUPLE_SWAP_INTERACTION : "replaces"
```