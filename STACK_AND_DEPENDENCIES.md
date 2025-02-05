# Dependency Management
This project uses Swift Package Manager (SPM) integrated within Xcode for dependency management. We are NOT using SPM as a standalone package manager, but rather as Xcode's native package management solution.

## Adding Dependencies
1. In Xcode, go to File > Add Packages...
2. Enter the package URL (e.g., https://github.com/firebase/firebase-ios-sdk.git)
3. Select the desired version rules
4. Choose the target to add the package to

## Current Dependencies
- Firebase iOS SDK (via SPM)
  - FirebaseAuth
  - FirebaseFirestore (includes Swift extensions, formerly FirebaseFirestoreSwift)
  - FirebaseStorage

## Updating Dependencies
- Use Xcode's Package Dependencies tab in the project navigator
- Right-click > Update Package to update individual packages
- File > Packages > Update to Latest Package Versions to update all

## Resolving Issues
If you encounter package resolution issues:
1. Xcode > File > Packages > Reset Package Caches
2. Clean Build Folder (Cmd + Shift + K)
3. Build the project again

# Tech Stack
Frontend
Language: Swift
Framework: SwiftUI (or UIKit as needed)
Package Manager: Swift Package Manager
Build/Run: Sweetpad. I'm not aware of the commands to build and run with sweetpad. It uses VS Code configs. If you are aware, let me know.

Backend Services (via Firebase)
The backend is designed to handle user authentication, data storage, video recommendations, and serverless logic using Firebase. Firebase's serverless nature simplifies infrastructure management while allowing for scalability and rapid development.

Authentication & User Management
Decision: Firebase Auth
Supports email/password authentication.

Database Management
Decision: Firestore (NoSQL, real-time updates for user progress and interactions)
Purpose: Stores user interactions, video metadata, watch history, and swiped-away content to inform personalized recommendations.
Data Model: The database will store session-specific information (videos watched, videos swiped away) as well as long-term preference data.

Media Storage & Video Processing
Decision: Firebase Cloud Storage (for video files and thumbnails)
Purpose: Provides reliable media storage and access for video playback.

Backend Logic
Decision: Firebase Cloud Functions (serverless backend)
Purpose: Handles video processing, recommendation logic, AI-driven features, and integration with external APIs.
Description: Manages compute-intensive tasks like processing video interactions or dynamically updating the Inspirations grid based on swiping patterns.
Provides flexibility to integrate future AI models or external APIs without architectural changes.

## Development Requirements

- Python 3.9 or higher (required for xcode-build-server)
- Xcode and related development tools