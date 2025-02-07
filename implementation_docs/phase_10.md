## Phase 10: Multiswipe: Quick Video Removal Features

### Checklist
[ ] **Basic Swipe-to-Remove**: Add the ability for users to swipe left or right on any video in the grid to instantly remove it from view (like swiping emails in a mail app).

[ ] **Space-Based Multi-Remove**:
   - Add small gaps between videos in the grid
   - When a user swipes upward on a gap between videos, remove all videos that touch that gap
   - As soon as the swipe happens, the affected videos should smoothly animate upward and disappear

[ ] **Automatic Video Replacement**:
   - Every time a video is removed (whether by single swipe or gap swipe)
   - Immediately fetch a new random video from Firestore to replace it
   - Don't wait for all removals to complete before fetching replacements

[ ] **Smooth Grid Updates**:
   - After videos are removed and new ones are fetched
   - Smoothly animate the new videos into their positions in the grid
   - The grid should never appear empty or broken during this process

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── InspirationsGridView.swift (extend multi-swipe logic)
│   ├── Services
│   │   └── FirestoreService.swift (handle multiple fetch requests)
│   └── (other Swift/UI files)
└── (remaining project files)

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift`
```swift:TikTok-Clone/Controllers/Discover/DiscoverVC.swift
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
