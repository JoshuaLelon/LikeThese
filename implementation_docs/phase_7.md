## Phase 7: Autoplay
### Checklist
[x] Track the end of the current video and automatically load the next recommended video from Firestore.  
[x] Seamlessly replay or skip to next content upon video completion.  

### Warnings
- Ensure Firestore read rules permit fetching the next video.
- Verify that the hardcoded video URL in VideoPlaybackView is replaced in production.

### Change Log
- Added AVPlayer observer in VideoPlaybackView to trigger handleVideoEnd at video completion.
- Implemented handleVideoEnd to fetch the next recommended video via FirestoreService or replay the current video.
- Added fetchNextRecommendedVideo function in FirestoreService as per Phase 7 requirements.
- Fixed infinite retry issue in fetchReplacementVideo by:
  - Removing retry loop that could cause UI freezes
  - Adding proper error handling for no-next-video case
  - Implementing graceful fallback to replay current video
- No issues encountered after fixes.

### Implementation Notes
- When no replacement video is available in Firestore, the current video will replay instead of attempting infinite retries
- Added comprehensive logging to track video completion and replacement flow
- Used proper actor isolation and async/await patterns for video transitions

### Debugging
To view app logs (including video completion events):
```bash
xcrun simctl spawn booted log show --predicate 'process contains "LikeThese"' --debug --info --last 5m
```

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── VideoPlaybackView.swift (handle onVideoEnd -> fetchNextVideo)
│   ├── Services
│   │   └── FirestoreService.swift (add fetchNextRecommendedVideo)
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:

#### `TikTok-Clone/Controllers/VideoPlayer/VideoPlaybackVC.swift`
```swift:TikTok-Clone/Controllers/VideoPlayer/VideoPlaybackVC.swift
import UIKit
import AVKit
import FirebaseFirestore

// Example snippet for automatically loading the next recommended video
// when the current video finishes. You could attach this logic to a
// completion observer on AVPlayer or AVPlayerItem.

function handleVideoPlayback(url: URL) {
    let playerItem = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: playerItem)
    let playerLayer = AVPlayerLayer(player: player)
    // Add playerLayer to the view's layer...
    player.play()

    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: playerItem,
        queue: .main
    ) { [weak self] _ in
        self?.fetchNextRecommendedVideo()
    }
}

function fetchNextRecommendedVideo() {
    Firestore.firestore().collection("videos")
        .order(by: "timestamp", descending: true)
        .limit(to: 1)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error fetching next video: \(error.localizedDescription)")
                return
            }
            guard let document = snapshot?.documents.first,
                  let data = document.data()["videoUrl"] as? String,
                  let videoURL = URL(string: data) else {
                print("No more videos found.")
                return
            }
            print("Autoplaying next video: \(document.documentID)")
            // Play or load this next video
        }
}
```

#### `TikTok-Clone/Services/Analytics/PlaybackAnalytics.swift`
```swift:TikTok-Clone/Services/Analytics/PlaybackAnalytics.swift
import FirebaseFirestore
import FirebaseAuth
import Foundation

// Example snippet for storing autoplay events whenever
// a video completes and the next one automatically loads.

function logAutoplayEvent(currentVideoId: String, nextVideoId: String?) {
    guard let userId = Auth.auth().currentUser?.uid else {
        print("User not logged in. Skipping analytics logging.")
        return
    }
    var payload: [String: Any] = [
        "userId": userId,
        "currentVideoId": currentVideoId,
        "timestamp": Date()
    ]
    if let nextVideo = nextVideoId {
        payload["nextVideoId"] = nextVideo
    }
    Firestore.firestore().collection("autoplayEvents").addDocument(data: payload) { error in
        if let error = error {
            print("Error logging autoplay event: \(error.localizedDescription)")
        } else {
            print("Autoplay event logged successfully.")
        }
    }
}
```


