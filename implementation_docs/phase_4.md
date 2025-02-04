## Phase 4: Seeding the Database

### Prerequisites
1. Firebase project must be set up with:
   - Firestore database created and enabled (in test mode for MVP)
   - Storage enabled
   - Proper security rules configured
2. Local development environment must have:
   - Node.js and npm installed
   - Firebase CLI installed and logged in
   - ffmpeg installed (for thumbnail generation)

### Overview
We use a simple bash script that leverages the Firebase CLI to seed our database with test videos. The script:
1. Automatically generates thumbnails from videos using ffmpeg
2. Uploads videos and thumbnails to Firebase Storage
3. Creates Firestore documents linking to the uploaded files

### Checklist
[x] Create a small script or function that uploads sample videos and images (as video thumbnails) to Firestore.  
  - [x] Acquire 20 TikTok resolution videos for testing (1080x1920)
  - [x] Create bash script for handling uploads:
    - [x] Auto-generate thumbnails using ffmpeg
    - [x] Check for existing videos before upload
    - [x] Upload videos and thumbnails to Storage
    - [x] Create Firestore documents with URLs
  - [x] Make script executable: `chmod +x scripts/seed_videos.sh`
  - [x] Document script usage in README.md 
[x] Confirm data seeds appear in the Firestore console.  
  - [x] Create Firestore database in Firebase Console
    - Created in test mode for MVP
    - Default security rules allow read/write until March 6, 2025
    - Will need to update security rules before production
  - [x] Configure Firestore security rules (using test mode defaults for MVP)
  - [x] Enable Firebase Storage
    - Bucket URL: likethese-fc23d.firebasestorage.app
  - [x] Configure Storage security rules (using test mode defaults for MVP)
    - Default security rules allow read/write for 30 days
    - Will need to update security rules before production
  - [x] Run seeding script
  - [x] Verify data in Firebase Storage
    - Successfully uploaded 20 videos to Storage
    - Successfully generated and uploaded 20 thumbnails
    - All files accessible via gs://likethese-fc23d.firebasestorage.app/

### One-Time Setup
1. Install Node.js and npm (if not already installed):
   ```bash
   brew install node
   ```

2. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```

3. Install ffmpeg (for thumbnail generation):
   ```bash
   brew install ffmpeg
   ```

4. Log into Firebase:
   ```bash
   firebase login
   ```

5. Make the script executable:
   ```bash
   chmod +x scripts/seed_videos.sh
   ```

### Adding Test Videos
1. Create the videos directory:
   ```bash
   mkdir -p sample_data/videos
   ```

2. Add your test videos:
   - Place 12 .mp4 files in `sample_data/videos/`
   - Videos must be 1080x1920 resolution (TikTok format)
   - Videos should be reasonably sized (a few MB each)

### Running the Seeder
1. From project root:
   ```bash
   ./scripts/seed_videos.sh
   ```

2. The script will:
   - Create thumbnails automatically in `sample_data/thumbnails/`
   - Upload videos to Firebase Storage under `videos/`
   - Upload thumbnails to Firebase Storage under `thumbnails/`
   - Create a Firestore document for each video with:
     - Video URL
     - Thumbnail URL
     - Creation timestamp

3. Progress and errors will be shown in the terminal

### File Structure
LikeThese/
├── scripts
│   └── seed_videos.sh      # The main seeding script
├── sample_data
│   ├── videos             # Put your .mp4 files here
│   │   ├── video1.mp4
│   │   └── ...
│   └── thumbnails         # Generated automatically
│       ├── thumb1.jpg
│       └── ...
└── (remaining project files)

### Warnings
- Videos must be TikTok resolution (1080x1920)
- The seeding process requires Firebase CLI and login
- Large videos may take time to upload
- Make sure you have enough Firebase Storage quota
- Script is idempotent (safe to run multiple times)
- Already uploaded videos will be skipped
- Firebase CLI must be installed (`npm install -g firebase-tools`)
- ffmpeg must be installed (`brew install ffmpeg`)
- Must be logged into Firebase CLI (`firebase login`)
- Sample videos must be in .mp4 format
- Ensure your Firebase project has Storage and Firestore enabled
- Database is in test mode - DO NOT USE FOR PRODUCTION
- Current security rules expire on March 6, 2025
- Must update security rules within 30 days for production use

### Files from another repository to use for inspiration:
- TikTok-Clone/Controllers/Create Post/CreatePostVC.swift  
  • Code for uploading data to Firebase (useful pattern for a seeding script)  
- TikTok-Clone/Controllers/Discover/DiscoverVC.swift  
  • Showcases how lists of content are fetched from Firebase and displayed  
- Pods/FirebaseAuth/README.md  
  • If your database-seeding depends on authenticated user roles or requires user context


#### `TikTok-Clone/Controllers/Create Post/CreatePostVC.swift`
```swift:TikTok-Clone/Controllers/Create Post/CreatePostVC.swift
// (Repeated or similar snippet from above; can be repurposed for seeding the database.)
function seedInitialVideos() {
    // Example usage: uploading multiple sample videos for the initial seed.
    // ...
}
```

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift`
```swift:TikTok-Clone/Controllers/Discover/DiscoverVC.swift
import UIKit
import FirebaseFirestore

// Example snippet to fetch a list of "seeded" videos from Firestore and display them.

function loadSeededVideos() {
    Firestore.firestore().collection("videos").getDocuments { snapshot, error in
        if let error = error {
            print("Error fetching seeded videos: \(error.localizedDescription)")
            return
        }
        let documents = snapshot?.documents ?? []
        for doc in documents {
            print("Found seeded video with ID: \(doc.documentID) data: \(doc.data())")
        }
    }
}
```