## Phase 6: Video Replacement (Swipe Up)

### Considerations
- Need to determine optimal video preloading strategy for smooth transitions
- Need to decide on video replacement animation style
- Consider implementing video caching for better performance
- [DECISION NEEDED] Determine retry strategy for network failures
- [DECISION NEEDED] Define offline behavior for video playback

### Checklist
[x] When user swipes up, fetch a replacement video from Firestore  
[x] Update the UI to show the new video in place  
[x] Optionally record an interaction document in Firestore to track the skip event  
[PROGRESS] Implement network error handling and retry logic  
[ ] Add loading state UI feedback  
[ ] Implement video preloading for next video  
[ ] Add offline mode support  

### Implementation Details
- Added smooth visual feedback during swipe gestures (opacity and scale animations)
- Implemented crossfade transition between videos
- Added interaction tracking in Firestore with timestamp and user ID
- Added error handling with visual feedback

### Debugging Log
#### Attempt 1 - Initial Implementation
**Plan:**
- Implement basic video fetching using FirestoreService
- Use SwiftUI animations for transitions
- Track skip interactions in Firestore

**Expected Behavior:**
- Smooth transition between videos
- New video loads immediately after swipe
- Skip interaction recorded in background

**Actual Behavior:**
- Network connectivity error (NSPOSIXErrorDomain, code:50)
- Video loading stuck
- Firebase connection failing

### Warnings
- ⚠️ Network connectivity issues detected - need robust error handling
- ⚠️ Need to ensure Firebase Storage rules are configured for video access
- ⚠️ Consider implementing video preloading to prevent playback delays
- ⚠️ Test video loading performance with different network conditions
- ⚠️ Monitor Firestore quotas for interaction tracking
- ⚠️ Need offline mode support for poor network conditions

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   ├── VideoPlaybackView.swift (✓ Created with swipe gestures and animations)
│   │   └── LoadingView.swift (Needed for loading states)
│   ├── Services
│   │   ├── FirestoreService.swift (✓ Created with video fetching and interaction tracking)
│   │   └── NetworkMonitor.swift (Needed for network state monitoring)
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- TikTok-Clone/Controllers/Discover/DiscoverVC.swift
  • Show how vertical/horizontal swipe gestures can be implemented and trigger new data loads
- TikTok-Clone/Controllers/Notifications/NotificationsVC.swift
  • Useful for refreshing view data after an interaction (similar to replacing a video)
- TikTok-Clone/Services/NetworkMonitor.swift
  • Example of network state monitoring implementation

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift````swift:TikTok-Clone/Controllers/Discover/DiscoverVC.swift
import UIKit
import FirebaseFirestore

function handleAuthStatus() {
    // Suppose we have a user session; we might refresh
    // the view to show personalized content.

    Firestore.firestore().collection("videos").getDocuments { snapshot, error in
        if let error = error {
            print("Error refreshing videos: \(error.localizedDescription)")
            return
        }
        let documents = snapshot?.documents ?? []
        // Update the UI to reflect the newly fetched videos
        print("Refreshed content for user: \(documents.count) videos found.")
    }
}
```

#### `TikTok-Clone/Controllers/Notifications/NotificationsVC.swift`
```swift:TikTok-Clone/Controllers/Notifications/NotificationsVC.swift
import UIKit
import FirebaseAuth
import FirebaseFirestore

function handleUserNotifications() {
    guard let currentUser = Auth.auth().currentUser else {
        print("No logged-in user. Notifications might be restricted or shown differently.")
        return
    }

    Firestore.firestore().collection("notifications")
        .whereField("userId", isEqualTo: currentUser.uid)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error fetching notifications: \(error.localizedDescription)")
                return
            }
            let documents = snapshot?.documents ?? []
            print("User has \(documents.count) notifications to review.")
            // Update UI accordingly
        }
}
```