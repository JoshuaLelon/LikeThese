## Phase 10: Multiswipe: Quick Video Removal Features

### Checklist
[ ] **Basic Swipe-to-Remove**: Add the ability for users to swipe up on any video in the grid to instantly remove it from view (like swiping emails in a mail app).

### Implementation Issues and Solutions

#### Issue 1: Grid Layout Inconsistency During Video Removal
**Problem**: When a video is removed via swipe up, other videos sometimes move unexpectedly in the grid. This is caused by multiple grid state updates during the removal process.

**Relevant Logs**:
```
🔄 Swipe in progress - Video ID: yellow_hoodie_on_stool, Offset: -45.0
🗑️ Removing video with upward swipe - Video ID: yellow_hoodie_on_stool
🔄 Grid updated with 4 videos
```

**Solution Plan**:
1. Implement atomic video replacement
2. Use a transaction-like approach for video removal and replacement
3. Batch grid updates to prevent intermediate states

**Code Changes**:
Before:
```swift
// In VideoViewModel
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        videos.remove(at: index)
        
        do {
            let newVideo = try await firestoreService.fetchRandomVideo()
            videos.insert(newVideo, at: index)
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
        do {
            // Fetch replacement before removing
            let newVideo = try await firestoreService.fetchRandomVideo()
            
            // Perform update atomically
            await MainActor.run {
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                videos = updatedVideos // Single update
            }
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

#### Issue 3: Black Rectangle After Video Removal
**Problem**: After swiping up a video, it's sometimes replaced with a black rectangle. This occurs due to a race condition between removing the old video and inserting the new one.

**Relevant Logs**:
```
🗑️ Removing video with upward swipe - Video ID: yellow_hoodie_on_stool
🔄 Grid updated with 4 videos
```

The logs show that while the grid is updating, there's no confirmation of successful video replacement. The issue occurs because:
1. The video is removed from the array
2. The grid updates immediately
3. The new video fetch happens asynchronously
4. During this async gap, a black rectangle appears

**Solution Plan**:
1. Fetch replacement video BEFORE removing the old one
2. Use atomic updates to ensure grid only updates once
3. Add loading state during transition
4. Implement proper error recovery

Before:
```swift
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        videos.remove(at: index)
        do {
            let newVideo = try await firestoreService.fetchRandomVideo()
            videos.insert(newVideo, at: index)
        } catch {
            self.error = error
        }
    }
}
```

After:
```swift
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        do {
            // Set loading state
            await MainActor.run {
                replacingVideoId = videoId
            }
            
            // Fetch new video first
            let newVideo = try await firestoreService.fetchRandomVideo()
            
            // Atomic update
            await MainActor.run {
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                videos = updatedVideos
                replacingVideoId = nil
            }
        } catch {
            await MainActor.run {
                self.error = error
                replacingVideoId = nil
            }
        }
    }
}
```

This solution will work because:
1. The loading state prevents visual glitches
2. Fetching before removing ensures smooth transition
3. Atomic updates prevent intermediate states
4. Error handling ensures cleanup of loading state

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

**Expected Outcomes**:
1. Grid layout remains stable during video removal
2. No black rectangles during video replacement
3. Smooth transitions between video states
4. Consistent grid appearance throughout the process
5. Clear separation between swipe and tap gestures
6. No unintended navigation during swipes
7. Improved user experience

#### Issue 5: Black Rectangle After Video Removal (Updated Solution)
**Problem**: After swiping up a video, it's sometimes replaced with a black rectangle. This occurs due to a race condition between removing the old video and inserting the new one.

**Relevant Logs**:
```
🗑️ Removing video with upward swipe - Video ID: yellow_hoodie_on_stool
🔄 Grid updated with 4 videos
```

The logs show that while the grid is updating, there's no confirmation of successful video replacement. The issue occurs because:
1. The video is removed from the array
2. The grid updates immediately
3. The new video fetch happens asynchronously
4. During this async gap, a black rectangle appears

**Solution Plan**:
1. Fetch replacement video BEFORE removing the old one
2. Use atomic updates to ensure grid only updates once
3. Add loading state during transition
4. Implement proper error recovery

Before:
```swift
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        videos.remove(at: index)
        do {
            let newVideo = try await firestoreService.fetchRandomVideo()
            videos.insert(newVideo, at: index)
        } catch {
            self.error = error
        }
    }
}
```

After:
```swift
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        do {
            // Set loading state
            await MainActor.run {
                replacingVideoId = videoId
            }
            
            // Fetch new video first
            let newVideo = try await firestoreService.fetchRandomVideo()
            
            // Atomic update
            await MainActor.run {
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                videos = updatedVideos
                replacingVideoId = nil
            }
        } catch {
            await MainActor.run {
                self.error = error
                replacingVideoId = nil
            }
        }
    }
}
```

This solution will work because:
1. The loading state prevents visual glitches
2. Fetching before removing ensures smooth transition
3. Atomic updates prevent intermediate states
4. Error handling ensures cleanup of loading state

#### Issue 6: Video Playback Navigation Failure
**Problem**: When tapping a video to play it, the app shows "No player found for index X" error. This occurs due to a race condition in player initialization and cleanup.

**Relevant Logs**:
```
👆 Grid selection - Video ID: woman_on_phone, Index: 1, Grid Position: 0,1
❌ PLAYBACK ERROR: No player found for index 1
❌ VIDEO PLAYER: No player available for index 1
```

The issue occurs because:
1. VideoManager cleanup is too aggressive
2. Players are being cleaned up during view transitions
3. Navigation happens before player initialization completes

**Solution Plan**:
1. Implement proper player lifecycle management
2. Add player readiness verification before navigation
3. Prevent cleanup during transitions
4. Add retry mechanism for failed player initialization

Before:
```swift
func preloadAndNavigate(to index: Int) async {
    videoManager.prepareForPlayback(at: index)
    try await videoManager.preloadVideo(url: url, forIndex: index)
    selectedVideo = video
    selectedIndex = index
    isVideoPlaybackActive = true
}
```

After:
```swift
func preloadAndNavigate(to index: Int) async throws {
    guard let video = gridVideos[safe: index],
          let url = URL(string: video.url) else {
        throw NavigationError.invalidVideo
    }
    
    // Set loading state
    await MainActor.run {
        preloadingIndex = index
    }
    
    do {
        // Prepare for transition
        videoManager.prepareForPlayback(at: index)
        
        // Preload with verification
        try await videoManager.preloadVideo(url: url, forIndex: index)
        
        // Verify player is ready
        guard let player = videoManager.player(for: index),
              player.currentItem?.status == .readyToPlay else {
            throw NavigationError.playerNotReady
        }
        
        // Navigate only when ready
        await MainActor.run {
            selectedVideo = video
            selectedIndex = index
            isVideoPlaybackActive = true
            preloadingIndex = nil
        }
    } catch {
        await MainActor.run {
            preloadingIndex = nil
            errorMessage = error.localizedDescription
            showError = true
        }
        throw error
    }
}
```

This solution will work because:
1. Player readiness is verified before navigation
2. Loading state prevents premature navigation
3. Error handling provides user feedback
4. Cleanup is prevented during transitions

#### Issue 7: Video Navigation Readiness
**Problem**: When tapping a video thumbnail, navigation fails with "video not ready" error even though logs show successful preloading. This occurs because we're not properly waiting for the player to be fully ready for playback.

**Relevant Logs**:
```
🎮 TRANSITION: Preparing for video playback at index 0
🔄 PRELOAD: Starting preload for index 0
✅ PRELOAD: Successfully preloaded video at index 0
🎮 BUFFER STATE: Video 0 buffering: false
```

The issue occurs because:
1. Video preloads successfully
2. Buffer state shows as not buffering
3. But player readiness check is too strict
4. Navigation fails before player is fully ready

**Solution Plan**:
1. Implement proper player readiness verification
2. Add retry mechanism for player initialization
3. Show loading state during the entire process
4. Add timeout to prevent infinite waiting

Before:
```swift
private func navigateToVideo(at index: Int) async {
    guard let video = gridVideos[safe: index],
          let url = URL(string: video.url) else {
        errorMessage = "Invalid video URL"
        showError = true
        return
    }
    
    preloadingIndex = index
    
    do {
        videoManager.prepareForPlayback(at: index)
        try await videoManager.preloadVideo(url: url, forIndex: index)
        
        guard let player = videoManager.player(for: index),
              player.currentItem?.status == .readyToPlay else {
            throw NSError(domain: "com.Gauntlet.LikeThese", code: -1, 
                userInfo: [NSLocalizedDescriptionKey: "Video player not ready"])
        }
        
        selectedVideo = video
        selectedIndex = index
        isVideoPlaybackActive = true
        preloadingIndex = nil
    } catch {
        preloadingIndex = nil
        errorMessage = error.localizedDescription
        showError = true
    }
}
```

After:
```swift
private func navigateToVideo(at index: Int) async {
    guard let video = gridVideos[safe: index],
          let url = URL(string: video.url) else {
        errorMessage = "Invalid video URL"
        showError = true
        return
    }
    
    preloadingIndex = index
    
    do {
        // Prepare for playback
        videoManager.prepareForPlayback(at: index)
        
        // Preload with progress tracking
        try await videoManager.preloadVideo(url: url, forIndex: index)
        
        // Wait for player to be ready with timeout
        try await withTimeout(seconds: 5) {
            while true {
                if let player = videoManager.player(for: index),
                   player.currentItem?.status == .readyToPlay,
                   player.currentItem?.isPlaybackLikelyToKeepUp == true {
                    return
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        // Navigate when ready
        selectedVideo = video
        selectedIndex = index
        isVideoPlaybackActive = true
        preloadingIndex = nil
    } catch {
        preloadingIndex = nil
        errorMessage = error.localizedDescription
        showError = true
    }
}

private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NSError(domain: "com.Gauntlet.LikeThese", code: -1, 
                userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

This solution will work because:
1. We properly wait for player to be fully ready
2. We have a timeout to prevent infinite waiting
3. We check both `readyToPlay` and `isPlaybackLikelyToKeepUp`
4. Loading state is shown during the entire process

#### Issue 8: Persistent Loading State During Video Replacement
**Problem**: During video swipe removal, sometimes an empty black rectangle appears instead of a loading indicator. This happens because the loading state isn't consistently maintained during the entire replacement process.

**Relevant Logs**:
```
🔄 Grid updated with 4 videos
```

The logs show only grid updates but no loading state transitions, indicating the loading state isn't being properly tracked and displayed.

**Solution Plan**:
1. Implement persistent loading state
2. Add loading state transitions
3. Ensure loading indicator is always visible
4. Handle edge cases and errors

Before:
```swift
private func gridItem(video: Video, index: Int) -> some View {
    let isReplacing = video.id == viewModel.replacingVideoId
    
    AsyncImage(url: video.thumbnailUrl.flatMap { URL(string: $0) }) { phase in
        // ... image handling
        if isReplacing {
            Color.black.opacity(0.5)
            ProgressView()
        }
    }
}
```

After:
```swift
private func gridItem(video: Video, index: Int) -> some View {
    let isReplacing = video.id == viewModel.replacingVideoId
    let isLoading = isReplacing || viewModel.isLoadingVideo(video.id)
    
    AsyncImage(url: video.thumbnailUrl.flatMap { URL(string: $0) }) { phase in
        ZStack {
            switch phase {
            case .empty:
                LoadingView(message: "Loading thumbnail...")
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                LoadingView(message: "Failed to load", isError: true)
            @unknown default:
                LoadingView(message: "Loading...")
            }
            
            if isLoading {
                Color.black.opacity(0.7)
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(isReplacing ? "Replacing video..." : "Loading...")
                        .foregroundColor(.white)
                        .font(.caption)
                }
            }
        }
    }
    .transition(.opacity)
    .animation(.easeInOut, value: isLoading)
}
```

This solution will work because:
1. Loading state is always visible during transitions
2. Loading indicator includes helpful text
3. Smooth animations prevent jarring transitions
4. Edge cases are handled with appropriate UI feedback

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
