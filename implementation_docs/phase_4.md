## Phase 4: Seeding the Database

### Overview
We use a simple bash script that leverages the Firebase CLI to seed our database with test videos. The script:
1. Automatically generates thumbnails from videos using ffmpeg
2. Uploads videos and thumbnails to Firebase Storage
3. Creates Firestore documents linking to the uploaded files

### Checklist
[PROGRESS] Create a small script or function that uploads sample videos and images (as video thumbnails) to Firestore.  
  - [ ] Acquire 12 TikTok resolution videos for testing (1080x1920)
  - [x] Create bash script for handling uploads:
    - [x] Auto-generate thumbnails using ffmpeg
    - [x] Check for existing videos before upload
    - [x] Upload videos and thumbnails to Storage
    - [x] Create Firestore documents with URLs
  - [ ] Make script executable: `chmod +x scripts/seed_videos.sh`
  - [x] Document script usage in README.md
[ ] Test retrieval of sample data in the app.  
[ ] Confirm data seeds appear in the Firestore console.  

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

#### `Pods/FirebaseAuth/README.md`
```markdown:Pods/FirebaseAuth/README.md
# Placeholder for FirebaseAuth README

This file would typically describe set up notes and examples for
configuring FirebaseAuth in your iOS project:
- Enabling Email/Password sign-in
- Adding OAuth providers
- Handling user sessions and tokens

See official docs for details:
https://firebase.google.com/docs/auth
```