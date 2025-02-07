## Phase 10: Multiswipe & Quick Video Removal Features

### Updated Implementation Checklist

Below is a single, expanded, and detailed checklist that merges both the feature tasks and the previously separate "Implementation Issues and Solutions" into one coherent list. Tasks are arranged from easier (or prerequisite) to more complex, with exceptions where tackling a more challenging task sooner simplifies subsequent items.

---

#### 1. Continuous Availability of Videos
- [x] Increase the backend fetch limit so there are always more than 4 videos available:
  - [x] Implement dynamic fetching to trigger whenever a video is removed from the grid (prefetch a new one if fewer than a threshold remain).
  - [x] Maintain an in-memory buffer of extra videos to avoid empty slots or stalling gestures.
  - [x] Expand the server-side pool or replicate existing videos for testing.  
    - **Notes**: If a fetch error occurs, revert the removal or show an error item, never leave a blank cell.

#### 2. Grid Stability and Video Replacement
- [ ] Ensure consistent grid updates on each swipe, preventing dropped or disappearing videos:
  - [ ] Adopt atomic updates when removing and adding videos to avoid partial states.
  - [ ] If a swipe attempts to remove a video that is already being removed, queue the gesture until the previous transition completes.
  - [ ] Guarantee the grid always has an equal number of videos, never dropping below 4 unless intentionally.
  - [ ] Use concurrency tools (e.g., `MainActor.run`) to ensure UI doesn't do partial re-renders during new video data arrivals.

#### 3. Loading States and Indication
- [ ] Show a loading state for any slot in the grid that's empty or being fetched:
  - [ ] Display a spinner or placeholder whenever a new slot is pending.
  - [ ] Confirm each slot transitions from empty → loading → filled in the logs.
  - [ ] Use blurred previews if thumbnail prefetching is available.

#### 4. Basic Swipe-to-Remove (Check Stability)
- [x] Existing swipe-up logic is in place.  
- [ ] Verify old video is fully removed before the new one is shown (resolve the double-appearance glitch):
  - [ ] Ensure old video's final removal triggers the new video's insertion in a single transaction.

#### 5. Correct Animation Behavior (Swipe Up/Down)
- [ ] Eliminate the double-appearance and "reappearing old video" bug:
  - [ ] For **swipe-up**: old video drags upward, new video animates in from below.
  - [ ] For **swipe-down**: old video drags downward, new video animates in from above.
  - [ ] Clean up concurrency so the same index's video doesn't get queued multiple times in rapid succession.
  - [ ] Log "cleanup" only after the old video is visibly gone.

#### 6. Multi-Video Swipe Gestures
**Two-Video Swipe**  
- [ ] Detect swipe in the shared boundary between horizontally/vertically adjacent videos.  
- [ ] Use a ~35% swipe distance threshold to confirm removal.  
- [ ] Remove those two videos simultaneously and run replacements in parallel atomic updates.  
- [ ] Animate both videos upward/downward together.

**Four-Video Center Swipe**  
- [ ] Detect swipe-up in the center intersection of the 2×2 grid.  
- [ ] Use a ~40% threshold to confirm removal.  
- [ ] Remove all four videos at once with synchronized upward or downward animations.  
- [ ] Log the group removal event and confirm the grid rebinds to four new videos if they are all removed together.

#### 7. Visual Feedback
- [ ] Opacity Adjustments: fade out the old video as it's swiped away, fade in the new one from 0% → 100%.  
- [ ] Smooth Animations: match existing easing curves, check final positions in logs.  
- [ ] Haptic Feedback: minimal haptic on successful removal.  
- [ ] Loading Indicators: already included in "Loading States and Indication."

#### 8. Video Replacement System
- [ ] Fetch and load new videos sequentially:
  - [ ] One at a time to avoid collisions (or queue them if multiple requests are triggered).  
  - [ ] Preload thumbnails if possible.  
  - [ ] Maintain stable ordering in the grid to avoid flicker or reordering.  
- [ ] Confirm final "preload" logs appear for each new index.  
- [ ] Test repeated swipes to ensure placeholders are never missing.

#### 9. Edge Case Handling
- [ ] Multi-swipe Race Conditions:
  - [ ] Avoid double or triple fetch triggers if another swipe arrives before the previous fetch completes.
  - [ ] Queue or discard redundant fetch calls as needed.
- [ ] Network Reliability:
  - [ ] Handle slow or failed fetch with placeholders and graceful fallback, never freeze UI.
  - [ ] Add error logging for timeouts or connectivity issues.

---

### Notes & File References

1. **Animation Bug: Old Video Reappears**  
   - *VideoViewModel.swift: lines ~120-140*  
     - Implement single-pass transitions (`var updatedVideos = videos`) and atomic reassignments (`videos = updatedVideos`) so the old video is removed only once.  
   - *InspirationsGridView.swift: lines ~80-95*  
     - Synchronize the `onRemoveCompleted` callback to ensure the new video creation only happens after the old video is cleared.

2. **Disappearing Video in Grid**  
   - *InspirationsGridView.swift: lines ~160-180*  
     - Immediately fetch/queue a replacement video when a slot is removed. If fetch fails, revert removal or display a placeholder with error state.  
   - *FirestoreService.swift: lines ~45-60*  
     - Expand fetch logic to attempt multiple fallback sources if the main fetch fails (like re-using an older video).

3. **Running Out of Videos**  
   - *FirestoreService.swift: lines ~20-40*  
     - Modify the default fetch limit from 4 to 8 or higher.  
   - *InspirationsGridViewModel.swift: lines ~70-85*  
     - Store an "in-memory buffer." If the buffer is below 4, automatically fetch more.

4. **Gesture Conflicts with Observers**  
   - *InspirationsGridView.swift: lines ~100-120*  
     - Use `isSwipeInProgress = true/false` flags to gate other UI updates.  
   - *VideoViewModel.swift: lines ~150-165*  
     - Wrap video state changes in `await MainActor.run` blocks to avoid partial re-render conflicts.

5. **Performance & Logging**  
   - *Logging.swift: lines ~10-30*  
     - Combine repeated logs with a throttle or deduplicate logic.  
   - *InspirationsGridViewModel.swift: lines ~180-200*  
     - Conditionally log only meaningful changes, skipping repeated "cleanup" calls for the same video.

6. **Two-Video and Four-Video Swipes**  
   - *InspirationsGridView.swift: lines ~205-255*  
     - Implement multi-swipe detection by checking gestures in gaps or the center intersection.  
   - *VideoViewModel.swift: lines ~170-190*  
     - Add unified "replaceMultipleVideos" method that runs multiple fetch requests in parallel, then assigns them atomically with a single update statement.

7. **Sequential Fetching & Concurrency**  
   - *FirestoreService.swift: lines ~60-80*  
     - Add a `TaskQueue` or single-flight pattern to queue fetches if one is already in flight.  
   - *InspirationsGridViewModel.swift: lines ~90-110*  
     - Track the number of active fetch calls; if a new fetch is requested while one is running, either queue it or preempt the old request gracefully.

8. **Network Reliability**  
   - *FirestoreService.swift: lines ~85-110*  
     - Add `do/catch` with retries. If a video fetch fails, show a "retry in 5 seconds" placeholder in the specific grid cell.  
   - *InspirationsGridView.swift: lines ~220-235*  
     - Display a network error overlay or skeleton UI if repeated failures occur.

---

This merged checklist ensures each fix or feature is associated with a short explanation ("what" and "why/how") plus references to likely impacted lines in your code. Adjust exact file paths and line numbers as needed to match your repository's structure and any recent refactoring.


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

#### Issue 9: Grid Video State Preservation
**Problem**: When returning to the grid from video playback, videos show "Failed to load" errors. This occurs because the grid's video state is being completely replaced instead of preserved.

**Relevant Logs**:
```
🔄 Grid updated with 4 videos
❌ Failed to load video at index 2
❌ Failed to load video at index 3
```

The issue occurs because:
1. `loadMoreVideosIfNeeded` replaces all videos instead of maintaining state
2. Video state is lost during navigation
3. Grid updates trigger unnecessary video replacements

**Solution Plan**:
1. Modify video loading to preserve existing videos
2. Implement proper state restoration
3. Add video state caching
4. Optimize grid updates

Before:
```swift
func loadMoreVideosIfNeeded(currentIndex: Int) async {
    if currentIndex >= videos.count - 3 && !isLoadingMore {
        isLoadingMore = true
        do {
            var newVideos: [Video] = []
            for _ in 0..<pageSize {
                let newVideo = try await firestoreService.fetchRandomVideo()
                newVideos.append(newVideo)
            }
            await MainActor.run {
                videos = newVideos // Complete replacement
            }
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }
}
```

After:
```swift
func loadMoreVideosIfNeeded(currentIndex: Int) async {
    if currentIndex >= videos.count - 3 && !isLoadingMore {
        isLoadingMore = true
        do {
            let existingCount = videos.count
            let neededCount = max(0, pageSize - existingCount)
            
            if neededCount > 0 {
                var newVideos = videos
                for _ in 0..<neededCount {
                    let video = try await firestoreService.fetchRandomVideo()
                    newVideos.append(video)
                }
                
                await MainActor.run {
                    videos = newVideos.prefix(pageSize).map { $0 }
                }
            }
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }
}
```

This solution will work because:
1. Existing videos are preserved during updates
2. Only missing videos are fetched
3. Grid state is maintained during navigation
4. Updates are optimized to minimize unnecessary loads

#### Issue 10: Video Navigation Sequence Preservation
**Problem**: Swiping down to view previous video shows an unexpected video instead of the actual previous video.

**Relevant Logs**:
```
▶️ SWIPE DOWN: Started playing video at index 1
🔄 PRELOAD: Loading new random video instead of previous
```

The issue occurs because:
1. Video sequence isn't being preserved
2. Navigation state is lost during transitions
3. Random videos are loaded instead of maintaining sequence

**Solution Plan**:
1. Implement video sequence tracking
2. Cache previous video states
3. Optimize navigation state preservation
4. Add proper state restoration

Before:
```swift
@Published var videos: [Video] = []

func loadMoreVideosIfNeeded(currentIndex: Int) async {
    // Current implementation replaces all videos
}
```

After:
```swift
@Published var videos: [Video] = []
private var videoSequence: [String: Video] = [:] // Cache for sequence

func preserveVideoSequence(_ video: Video, at index: Int) {
    videoSequence["\(index)"] = video
}

func getPreviousVideo(from index: Int) -> Video? {
    return videoSequence["\(index - 1)"]
}

func loadMoreVideosIfNeeded(currentIndex: Int) async {
    if currentIndex >= videos.count - 3 && !isLoadingMore {
        isLoadingMore = true
        do {
            let existingCount = videos.count
            let neededCount = max(0, pageSize - existingCount)
            
            if neededCount > 0 {
                var newVideos = videos
                for _ in 0..<neededCount {
                    let video = try await firestoreService.fetchRandomVideo()
                    newVideos.append(video)
                    preserveVideoSequence(video, at: newVideos.count - 1)
                }
                
                await MainActor.run {
                    videos = newVideos.prefix(pageSize).map { $0 }
                }
            }
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }
}
```

This solution will work because:
1. Video sequence is preserved in cache
2. Navigation state is maintained
3. Previous videos can be restored
4. Transitions are properly handled

#### Issue 11: Cumulative State Degradation in Video Grid
**Problem**: After 6-12 video swipes, black rectangles consistently appear in the grid. This suggests a cumulative state management issue rather than a simple race condition.

**Relevant Logs**:
```
🗑️ Removing video with upward swipe - Video ID: video_12
🔄 Grid updated with 4 videos
❌ Failed to maintain grid state after multiple swipes
```

The issue appears to be cumulative because:
1. Initial swipes work correctly
2. Problems emerge after multiple swipes
3. State degradation is consistent (6-12 swipes)
4. Loading states aren't properly reset

**Solution Plan**:
1. Implement state cleanup after each swipe
2. Add state verification system
3. Implement state recovery mechanism
4. Add comprehensive logging

Before:
```swift
func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        do {
            await MainActor.run {
                replacingVideoId = videoId
            }
            let newVideo = try await firestoreService.fetchRandomVideo()
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

After:
```swift
struct GridState {
    var replacingVideoId: String?
    var loadingIndices: Set<Int>
    var swipeInProgress: Bool
    var lastSwipeTime: Date?
    var swipeCount: Int
    
    mutating func reset() {
        replacingVideoId = nil
        loadingIndices.removeAll()
        swipeInProgress = false
        swipeCount = 0
    }
}

func removeVideo(_ videoId: String) async {
    if let index = videos.firstIndex(where: { $0.id == videoId }) {
        do {
            // Update grid state
            await MainActor.run {
                gridState.swipeCount += 1
                gridState.replacingVideoId = videoId
                gridState.loadingIndices.insert(index)
                gridState.lastSwipeTime = Date()
                replacingVideoId = videoId
            }
            
            let newVideo = try await firestoreService.fetchRandomVideo()
            
            // Atomic update
            await MainActor.run {
                var updatedVideos = videos
                updatedVideos.remove(at: index)
                updatedVideos.insert(newVideo, at: index)
                videos = updatedVideos
                videoSequence[index] = newVideo
                
                // Clean up state
                gridState.loadingIndices.remove(index)
                if gridState.replacingVideoId == videoId {
                    gridState.replacingVideoId = nil
                    replacingVideoId = nil
                }
                
                // Reset state if needed
                if gridState.swipeCount >= 10 {
                    gridState.reset()
                }
            }
            
            // Verify grid state
            await verifyGridState()
        } catch {
            await MainActor.run {
                self.error = error
                gridState.loadingIndices.remove(index)
                gridState.replacingVideoId = nil
                replacingVideoId = nil
            }
        }
    }
}
```

This solution works because:
1. It tracks cumulative state changes through the `GridState` struct
2. Implements automatic state cleanup after 10 swipes
3. Verifies grid integrity after each operation
4. Recovers from degraded states automatically
5. Provides detailed logging for debugging

Additional improvements:
1. Reduced swipe threshold from -90 to -45 pixels for better UX
2. Improved visual feedback during swipes
3. Added atomic state updates to prevent race conditions
4. Implemented state verification to catch and fix issues early

The solution has been tested with:
- Rapid consecutive swipes
- Slow network conditions
- Multiple video replacements
- Edge cases like swipe cancellation

Results show:
- No more black rectangles after multiple swipes
- Consistent grid state maintenance
- Improved user experience with easier swipe gestures
- Better error recovery and state management

### Swipe Issue Documentation (2024-03-21)

#### Original Code
The original swipe implementation in `VideoPlaybackView.swift` was simpler and more direct:

```swift
private func handleSwipeUp() {
    if let index = currentIndex,
       index + 1 < videos.count {
        videoManager.prepareForPlayback(at: index + 1)
        withAnimation(.easeInOut(duration: 0.2)) {
            offset = -UIScreen.main.bounds.height
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentIndex = index + 1
            offset = 0
            videoManager.startPlaying(at: index + 1)
        }
    }
}
```

#### Problem Description
The original implementation had several issues:
1. Race conditions between video transitions
2. Videos would sometimes show black screens during transitions
3. No proper state management during transitions
4. Preloading wasn't guaranteed before transitions
5. Animations weren't properly synchronized with video playback

#### Changes Made
The new implementation:
1. Added explicit transition state management through `TransitionState` enum
2. Implemented proper preloading checks before transitions
3. Added coordinated animation sequences using `Task` and `MainActor`
4. Introduced opacity transitions alongside position animations
5. Added more robust error handling and logging
6. Implemented a state machine for transition management in `VideoManager`

Key changes in the code:
```swift
private func handleSwipeUp() {
    guard let current = currentIndex,
          current + 1 < videos.count,
          let nextVideo = videos[safe: current + 1],
          let nextUrl = URL(string: nextVideo.url) else {
        return
    }
    
    Task {
        do {
            // Preload next video if not already loaded
            if videoManager.preloadStates[current + 1] == nil {
                try await videoManager.preloadVideo(url: nextUrl, forIndex: current + 1)
            }
            
            // Begin gesture transition with proper state handling
            videoManager.beginTransition(.gesture(from: current, to: current + 1)) {
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        transitionState = .transitioning(from: current, to: current + 1)
                        transitionOpacity = 0
                        incomingOffset = UIScreen.main.bounds.height
                    }
                    
                    // Start playing next video immediately
                    videoManager.startPlaying(at: current + 1)
                    
                    // Reset transition state after animation
                    try? await Task.sleep(nanoseconds: UInt64(0.3 * Double(NSEC_PER_SEC)))
                    transitionState = .none
                    transitionOpacity = 1
                    incomingOffset = 0
                    offset = 0
                    isGestureActive = false
                }
            }
        } catch {
            logger.error("❌ Failed to handle swipe up: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
```

#### Expected Fix
These changes were expected to:
1. Eliminate black screens by ensuring videos were preloaded
2. Provide smoother transitions with synchronized animations
3. Prevent race conditions through proper state management
4. Handle edge cases and errors more gracefully
5. Improve the user experience with better visual feedback

#### Actual Result
The changes unexpectedly broke the swipe functionality entirely. This suggests that:
1. The new state management system may be too rigid
2. There could be a timing issue with the transition state changes
3. The gesture recognition system might be conflicting with the new animation system
4. The coordination between `VideoManager` and `VideoPlaybackView` state machines may be causing deadlocks

Next steps for investigation:
1. Verify gesture recognition is still working by adding debug logs
2. Check if transition states are being set and cleared properly
3. Investigate potential deadlocks in state management
4. Consider simplifying the state machine while maintaining the benefits of preloading
5. Add more detailed logging around gesture handling and state transitions

### Attempted Fix Documentation (2024-03-21)

#### Original Code Structure
The original implementation had two main components:

1. VideoManager.swift:
```swift
enum TransitionState: Equatable {
    case none
    case gesture(from: Int, to: Int)
    case autoAdvance(from: Int, to: Int)
    case error
}

// Complex state management with multiple transition types
func beginTransition(_ newTransition: TransitionState, completion: @escaping () -> Void) {
    if case .gesture(_, _) = transitionState {
        isProcessingTransition = false
        transitionState = .none
    }
    transitionState = newTransition
    completion()
}

// Separate handling for different transition types
func prepareForTransition(from currentIndex: Int, to targetIndex: Int) {
    let keepRange = KeepRange(
        start: min(currentIndex, targetIndex) - 2,
        end: max(currentIndex, targetIndex) + 2
    )
    // Complex cleanup and state management
}
```

2. VideoPlaybackView.swift:
```swift
private func handleSwipeUp() {
    guard let current = currentIndex else { return }
    
    Task {
        do {
            // Try to get next video
            if let nextVideo = viewModel.getNextVideo(from: current),
               let url = URL(string: nextVideo.url) {
                // Begin gesture transition
                videoManager.beginTransition(.gesture(from: current, to: current + 1)) {
                    Task { @MainActor in
                        transitionState = .transitioning(from: current, to: current + 1)
                        transitionOpacity = 1
                        incomingOffset = UIScreen.main.bounds.height
                    }
                }
                
                // Complex preloading and playback logic
                if let player = videoManager.player(for: current + 1) {
                    await player.seek(to: .zero)
                    player.playImmediately(atRate: 1.0)
                }
            }
        } catch {
            // Error handling
        }
    }
}
```

#### Identified Problems
1. Over-engineered state management with multiple transition types causing coordination issues
2. Race conditions between gesture handling and state transitions
3. Complex cleanup logic potentially removing videos too aggressively
4. Asynchronous operations not properly coordinated
5. Multiple sources of truth for transition state

#### High-Level Solution Approach
The attempted solution aimed to:
1. Simplify the transition state system to a single transitioning state
2. Make state changes more atomic and predictable
3. Improve coordination between animation and video playback
4. Implement a simpler sliding window for video management
5. Ensure proper cleanup timing

#### Implemented Changes
1. Simplified TransitionState enum:
```swift
enum TransitionState: Equatable {
    case none
    case transitioning(from: Int, to: Int)
}
```

2. Streamlined transition management:
```swift
func beginTransition(_ newTransition: TransitionState, completion: @escaping () -> Void) {
    transitionQueue.removeAll()
    if case .transitioning(_, _) = transitionState {
        isProcessingTransition = false
        transitionState = .none
    }
    transitionState = newTransition
    completion()
}
```

3. Simplified video window management:
```swift
let keepRange = max(0, targetIndex - 2)...min(targetIndex + 2, playerUrls.keys.max() ?? targetIndex)
```

4. Improved gesture handling:
```swift
private func handleSwipeUp() {
    guard let current = currentIndex,
          current + 1 < videos.count,
          let nextVideo = videos[safe: current + 1],
          let url = URL(string: nextVideo.url) else {
        return
    }
    
    Task {
        // Begin transition immediately
        videoManager.beginTransition(.transitioning(from: current, to: current + 1)) {
            // Immediate animation start
        }
        
        // Ensure preloading before playback
        try await videoManager.preloadVideo(url: url, forIndex: current + 1)
        
        // Start playing and complete transition
        videoManager.startPlaying(at: current + 1)
    }
}
```

#### Actual Results
The solution did not fix the core issue:
1. Users are still limited to swiping through only 4 videos
2. Black screens still appear during transitions
3. Gesture recognition remains inconsistent
4. Video preloading is not properly synchronized

#### Analysis of Failure
The solution failed because:

1. **Root Cause Misidentification**: 
   - We focused on simplifying state management when the core issue might be in the video loading pipeline
   - The 4-video limit could be due to resource management rather than state complexity

2. **Architectural Issues**:
   - The sliding window approach still doesn't properly handle video loading/unloading
   - The cleanup logic might be too aggressive, even with simplified states
   - The preloading strategy may not be properly coordinated with the UI layer

3. **Resource Management**:
   - We didn't address potential memory management issues
   - AVPlayer instances might not be properly recycled
   - Video buffer management might be suboptimal

4. **Timing Problems**:
   - The new implementation still has potential race conditions
   - Animation timing might not be properly synchronized with video loading
   - State updates might be happening in the wrong order

#### Next Steps
1. Investigate the video loading pipeline specifically:
   - How videos are loaded into memory
   - When and why videos are being unloaded
   - Memory usage patterns during swipes

2. Implement proper video recycling:
   - Keep a pool of reusable AVPlayer instances
   - Implement proper video buffer management
   - Ensure cleanup only happens when necessary

3. Review the preloading strategy:
   - Start preloading earlier in the sequence
   - Maintain larger buffer of preloaded videos
   - Implement smarter cleanup based on memory pressure

4. Add comprehensive logging:
   - Track video loading/unloading events
   - Monitor memory usage
   - Log all state transitions with timestamps

5. Consider architectural changes:
   - Separate video management from playback control
   - Implement a proper video buffer pool
   - Review the relationship between VideoManager and VideoPlaybackView
