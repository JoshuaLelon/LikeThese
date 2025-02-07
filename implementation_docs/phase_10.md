## Phase 10: Multiswipe: Quick Video Removal Features

### Checklist
[ ] **Basic Swipe-to-Remove**: Add the ability for users to swipe up on any video in the grid to instantly remove it from view (like swiping emails in a mail app).

### Implementation Issues and Solutions

#### Issue 1: Array Index Mismatch
**Problem**: When removing a video and fetching a replacement, the new video is being appended to the end of the array instead of being inserted at the position of the removed video. This causes the grid layout to become inconsistent.

**Relevant Logs**:
```
🗑️ Removing video with upward swipe - Video ID: yellow_hoodie_on_stool
total videos: 4
total videos: 3
total videos: 4
```

**Solution Plan**:
1. Store the removal index when removing a video
2. Insert the replacement video at the same index
3. Maintain grid position consistency

**Code Changes**:
Before:
```swift
// In VideoViewModel
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        videos.remove(at: index)
        
        // Load a replacement video
        do {
            let newVideo = try await firestoreService.fetchRandomVideo()
            videos.append(newVideo)  // Wrong: Appending to end
        } catch {
            self.error = error
        }
    }
}
```

After:
```swift
// In VideoViewModel
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        videos.remove(at: index)
        
        // Load a replacement video
        do {
            let newVideo = try await firestoreService.fetchRandomVideo()
            videos.insert(newVideo, at: index)  // Correct: Insert at same position
        } catch {
            self.error = error
        }
    }
}
```

#### Issue 2: Grid Update Timing
**Problem**: The grid's state (`gridVideos`) isn't being updated when the videos array changes in the ViewModel, causing the grid to show stale data.

**Solution Plan**:
1. Add a publisher in the ViewModel to notify of video array changes
2. Update the grid's state when the videos array changes
3. Ensure smooth animations during updates

**Code Changes**:
Before:
```swift
// In InspirationsGridView
@State private var gridVideos: [Video] = []

// One-time initialization
.task {
    await viewModel.loadInitialVideos()
    gridVideos = viewModel.videos
}
```

After:
```swift
// In InspirationsGridView
@State private var gridVideos: [Video] = []

// Add video array observation
.onChange(of: viewModel.videos) { newVideos in
    withAnimation(.spring()) {
        gridVideos = newVideos
    }
}
```

**Expected Outcome**: These changes will ensure that:
1. Videos maintain their correct positions in the grid when removed and replaced
2. The grid updates smoothly when videos change
3. The user experience remains consistent during video removal and replacement

#### Issue 3: Grid Animation and State Management
**Problem**: The grid's state wasn't being properly updated when videos were removed and replaced, causing visual inconsistencies.

**Relevant Logs**:
```
🔄 Swipe in progress - Video ID: yellow_hoodie_on_stool, Offset: -45.0
🗑️ Removing video with upward swipe - Video ID: yellow_hoodie_on_stool
🔄 Grid updated with 4 videos
```

**Solution Plan**:
1. Add local grid state management
2. Implement proper animation timing
3. Handle state cleanup after removal

**Code Changes**:
```swift
// In InspirationsGridView
@State private var gridVideos: [Video] = []

// Add video array observation
.onChange(of: viewModel.videos) { newVideos in
    withAnimation(.spring()) {
        gridVideos = newVideos
    }
}
```

**Expected Outcome**: 
1. Smooth animations during video removal
2. Consistent grid state
3. Proper cleanup of removal states

#### Issue 4: Gesture Conflict Resolution
**Problem**: Swipe gestures were conflicting with tap gestures, causing unintended navigation.

**Solution Plan**:
1. Track swipe gesture state
2. Only allow taps when no swipe is in progress
3. Use simultaneous gesture recognition

**Code Changes**:
```swift
// In InspirationsGridView
@State private var isSwipeInProgress = false

.simultaneousGesture(
    DragGesture()
        .onChanged { value in
            isSwipeInProgress = true
            // ... gesture handling
        }
)
.onTapGesture {
    if !isSwipeInProgress {
        // ... handle tap
    }
}
```

**Expected Outcome**:
1. Clear separation between swipe and tap gestures
2. No unintended navigation during swipes
3. Improved user experience

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
