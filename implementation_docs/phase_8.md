## Phase 8: Previously Watched (Swipe Down)
### Checklist
[x] Maintain a stack or queue that records the user's watch history.  
[x] On swipe down, pop or shift the stack to reload the previously watched video.  
[ ] Display the previous video quickly from local cache or Firestore.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── VideoPlaybackView.swift (handle swipe down event)
│   ├── Services
│   │   └── HistoryManager.swift
│   └── (other Swift/UI files)
└── (remaining project files)

#### `TikTok-Clone/Services/Playback/PlaybackHistoryManager.swift`
```swift:TikTok-Clone/Services/Playback/PlaybackHistoryManager.swift
import Foundation
import FirebaseFirestore

// Example manager to track a user's watch history in a queue-like structure.
// You could store record IDs in Firestore or keep an in-memory queue first.

private var watchHistory: [String] = [] // Simplified; use a better data model.

func recordWatchedVideo(_ videoId: String) {
  watchHistory.append(videoId)
  // Optionally persist to Firestore if needed:
  // Firestore.firestore().collection("watchHistory").addDocument(data: [
  //   "videoId": videoId,
  //   "timestamp": Date()
  // ])
}

func getPreviousVideo() -> String? {
  guard watchHistory.count > 1 else { return nil }
  // Remove the last watched, then return the new last item
  _ = watchHistory.popLast()
  return watchHistory.last
}
```

#### `TikTok-Clone/Controllers/Playback/PlaybackViewController.swift`
```swift:TikTok-Clone/Controllers/Playback/PlaybackViewController.swift
import UIKit
import AVKit

// Example logic to handle "swipe down" for the previous video.
// Adjust or connect to your UI framework's gesture callbacks.

function setupSwipeDownGesture() {
  let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown(_:)))
  swipeDown.direction = .down
  view.addGestureRecognizer(swipeDown)
}

@objc
function handleSwipeDown(_ gesture: UISwipeGestureRecognizer) {
  guard let previousVideoId = getPreviousVideo() else {
    print("No previous video in history.")
    return
  }
  // Load previous video. For instance:
  // Firestore or local cache -> fetch metadata -> play video
  print("Loading previous video with ID: \(previousVideoId)")
}
```
