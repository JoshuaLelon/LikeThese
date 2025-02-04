## Phase 5: Implement Pause & Play (Single Video Playback)
### Checklist
[x] Integrate a basic video player (e.g., AVPlayer)  
[x] Add tap gesture on the video so it can pause/resume  
[x] Retrieve video from Firebase Storage  

### Building & Deploying
To rebuild and redeploy the app after making changes:

1. Using SweetPad UI:
   - Click the "Clean" option in the schema context menu
   - Click the "Build & Run" button (▶️)

2. Using Terminal:
   ```bash
   sweetpad clean && sweetpad build && sweetpad launch
   ```

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── VideoPlayerView.swift
│   ├── Services
│   │   └── StorageService.swift
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- TikTok-Clone/Controllers/Create Post/CreatePostVC.swift  
  • Illustrates how AVPlayer might be configured (for short video clips)  
- TikTok-Clone/Controllers/Details/TikTokDetailsVC.swift  
  • Demonstrates continuous playback flow and possible pause/resume logic

### Warnings
1. Ensure Firebase Storage is properly configured in your Firebase Console
2. Video playback may require background mode capability for continuous playback
3. Large video files may need optimization for smooth playback
4. Consider implementing video caching for better performance
5. Error handling is basic - consider adding user feedback for loading failures

#### `TikTok-Clone/Controllers/Create Post/CreatePostVC.swift`
```swift:TikTok-Clone/Controllers/Create Post/CreatePostVC.swift
import UIKit
import FirebaseFirestore
import FirebaseStorage

// Example snippet that shows how a new post might be structured/created
// in Firestore. Adjust depending on your actual schema.

function uploadNewVideo(_ videoData: Data, metadata: [String: Any]) {
    let storageRef = Storage.storage().reference().child("videos/\(UUID().uuidString).mp4")
    storageRef.putData(videoData, metadata: nil) { (storageMetadata, error) in
        if let error = error {
            print("Error uploading video: \(error.localizedDescription)")
            return
        }
        storageRef.downloadURL { (url, error) in
            guard let downloadURL = url else {
                print("Failed to retrieve download URL: \(String(describing: error))")
                return
            }
            Firestore.firestore().collection("videos").addDocument(data: [
                "videoUrl": downloadURL.absoluteString,
                "metadata": metadata,
                "timestamp": Date()
            ]) { err in
                if let err = err {
                    print("Error storing video data: \(err.localizedDescription)")
                } else {
                    print("Video data stored successfully.")
                }
            }
        }
    }
}
```

#### `TikTok-Clone/Controllers/Details/TikTokDetailsVC.swift`
```swift:TikTok-Clone/Controllers/Details/TikTokDetailsVC.swift
import UIKit
import FirebaseFirestore

// Example snippet showing how data might be retrieved and displayed.
// Adjust to your actual fields and UI.

function displayVideoDetails(_ videoDocumentID: String) {
    Firestore.firestore().collection("videos").document(videoDocumentID).getDocument { snapshot, error in
        if let error = error {
            print("Error fetching video details: \(error.localizedDescription)")
            return
        }
        guard let data = snapshot?.data() else {
            print("No data for this video.")
            return
        }
        // Do something with this data, e.g. update UI
        print("Fetched video data: \(data)")
    }
}
```