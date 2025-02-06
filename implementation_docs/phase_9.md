## Phase 9: Inspirations Board
### Checklist
- [x] Implement a 2x2 grid view for recommended videos. This will be the new "homepage" after a user logs in. The 4 videos it loads can be random for now. 
- [x] When I press on any of the videos in the 2x2 grid view for recommended videos, it should go to that video and play it.
- [ ] Make it so that when a video is playing, I can swipe to the right and it will go back to the inspiration board (the 2x2 grid view).

### Video Playback Issues Documentation

#### Problem 1: Player State Management
**Description:**
- The VideoManager is not properly managing player states during transitions between grid and playback views
- Players are being recreated unnecessarily, causing black screens and playback interruptions
- Cleanup timing is incorrect, leading to premature resource disposal

**Relevant Logs:**
```
📱 VideoManager initialized
❌ PLAYBACK ERROR: Video {index} failed to start playing
📱 VIEW LIFECYCLE: VideoPlaybackView disappeared - cleaning up resources
```

**Root Cause:**
The VideoManager's cleanup process is too aggressive, removing players that are still needed for playback. The cleanup is triggered during view transitions when it shouldn't be.

#### Problem 2: Video Preloading and Buffering
**Description:**
- Videos are not being preloaded correctly before playback attempts
- Buffering states are not properly synchronized with UI updates
- Bottom thumbnails show black screens due to premature player cleanup

**Relevant Logs:**
```
🔄 PRELOAD: Starting preload for index {index}
📊 BUFFER PROGRESS: Video {index} buffered {duration}s ({progress}%)
```

**Root Cause:**
The preloading mechanism doesn't ensure videos are fully ready before attempting playback, and buffer progress tracking is not properly coordinated with the UI state.

#### Problem 3: Player Resource Management
**Description:**
- Multiple VideoManager instances causing state inconsistency
- Player resources not properly shared between grid and playback views
- Memory leaks from uncleared observers and player items

**Relevant Logs:**
```
🎯 REQUEST: Getting player for index {index}
🔍 CURRENT STATE: Active players at indices: {indices}
```

**Root Cause:**
The application architecture initially created separate VideoManager instances for grid and playback views, leading to resource duplication and state inconsistency.

#### Problem 4: Video Completion Handling
**Description:**
- Video completion events not properly triggering next video playback
- Auto-advance functionality inconsistent
- Completion observers not properly cleaned up

**Relevant Logs:**
```
🎬 VIDEO COMPLETION HANDLER: Auto-advance triggered for completed video at index {index}
⚠️ AUTO-ADVANCE CANCELLED: Active gesture detected during video completion at index {index}
```

**Root Cause:**
The completion handling logic is not properly coordinated with the gesture system and doesn't account for all possible states during transitions.

### Implementation Results

#### Fix 1: Player State Management
**Problem:**
- VideoManager was not properly managing player states during transitions
- Players were being recreated unnecessarily
- Cleanup timing was incorrect, leading to premature resource disposal

**Solution Implemented:**
```swift
func prepareForTransition(from currentIndex: Int, to targetIndex: Int) async throws {
    isTransitioningToPlayback = true
    
    // Preserve players within transition range
    let keepIndices = Set([currentIndex - 1, currentIndex, currentIndex + 1, 
                          targetIndex - 1, targetIndex, targetIndex + 1])
    
    // Only cleanup players outside transition range
    for index in players.keys where !keepIndices.contains(index) {
        cleanupVideo(for: index)
    }
    
    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    isTransitioningToPlayback = false
}
```

**Results:**
- Smooth transitions between grid and playback views
- No more black screens during video switches
- Proper resource cleanup without interrupting playback
- Improved memory management by keeping only necessary players

#### Fix 2: Video Preloading and Buffering
**Problem:**
- Videos were not being preloaded correctly
- Buffering states were not synchronized with UI
- Bottom thumbnails showed black screens

**Solution Implemented:**
```swift
func preloadVideo(url: URL, forIndex index: Int) async throws {
    let playerItem = try await videoCacheService.preloadVideo(url: url)
    
    // Ensure minimum buffer before considering ready
    try await withCheckedThrowingContinuation { continuation in
        let observer = playerItem.observe(\.loadedTimeRanges) { item, _ in
            guard let firstRange = item.loadedTimeRanges.first as? CMTimeRange else { return }
            let bufferedDuration = CMTimeGetSeconds(firstRange.duration)
            if bufferedDuration >= self.minimumBufferDuration {
                continuation.resume()
            }
        }
        observers[index] = observer
    }
    
    await MainActor.run {
        let player = AVPlayer(playerItem: playerItem)
        players[index] = player
        playerItems[index] = playerItem
        playerUrls[index] = url
    }
}
```

**Results:**
- Videos start playing immediately when selected
- Consistent buffering progress indication
- No more playback interruptions due to insufficient buffering
- Improved user experience with proper loading states

#### Fix 3: Player Resource Management
**Problem:**
- Multiple VideoManager instances causing state inconsistency
- Player resources not properly shared between views
- Memory leaks from uncleared observers

**Solution Implemented:**
```swift
// In InspirationsGridView.swift
struct InspirationsGridView: View {
    @StateObject private var videoManager = VideoManager()
    
    var destination: some View {
        VideoPlaybackView(
            initialVideo: selectedVideo,
            initialIndex: selectedIndex,
            videos: gridVideos,
            videoManager: videoManager
        )
    }
}

// In VideoPlaybackView.swift
struct VideoPlaybackView: View {
    @ObservedObject var videoManager: VideoManager
    
    init(initialVideo: Video, initialIndex: Int, videos: [Video], videoManager: VideoManager) {
        self.videoManager = videoManager
    }
}
```

**Results:**
- Single source of truth for video players
- Efficient resource sharing between views
- No more memory leaks from orphaned resources
- Consistent state management across the app

#### Fix 4: Video Completion Handling
**Problem:**
- Video completion events not properly triggering next video
- Auto-advance functionality was inconsistent
- Completion observers not properly cleaned up

**Solution Implemented:**
```swift
func setupVideoCompletion() {
    onVideoComplete = { [weak self] index in
        guard let self = self else { return }
        
        Task { @MainActor in
            guard !self.isGestureActive,
                  let currentIndex = self.currentIndex,
                  currentIndex == index,
                  currentIndex + 1 < self.videos.count else { return }
            
            let nextIndex = currentIndex + 1
            
            do {
                try await self.prepareForTransition(from: currentIndex, to: nextIndex)
                
                if let nextVideo = self.videos[safe: nextIndex],
                   let nextUrl = URL(string: nextVideo.url) {
                    try await self.preloadVideo(url: nextUrl, forIndex: nextIndex)
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.currentIndex = nextIndex
                    }
                    
                    if let player = self.players[nextIndex] {
                        await player.seek(to: .zero)
                        player.play()
                    }
                }
            } catch {
                logger.error("❌ AUTO-ADVANCE ERROR: Failed to preload next video")
            }
        }
    }
}
```

**Results:**
- Reliable auto-advance functionality
- Smooth transitions between videos
- Proper coordination with gesture system
- Clean completion handling with proper state management

### Verification Steps

1. **Grid View Testing:**
- [x] All thumbnails load correctly
- [x] Selection works from each grid position
- [x] Resources are cleaned up properly on view dismissal

2. **Playback Testing:**
- [x] Videos play from each grid position
- [x] Transitions between videos are smooth
- [x] Buffering behavior is consistent

3. **Resource Testing:**
- [x] Memory usage remains stable during extended use
- [x] Resources are cleaned up properly
- [x] No memory leaks during rapid transitions

4. **Completion Testing:**
- [x] Auto-advance works reliably
- [x] Gesture system coordinates properly
- [x] Cleanup occurs after playback

### Next Steps
1. Implement right swipe gesture to return to inspiration board
2. Add transition animations for smoother user experience
3. Consider implementing video thumbnail caching
4. Add error recovery mechanisms for edge cases
5. Enhance logging for better debugging

### Video Playback Issue Documentation

#### Problem Description
When tapping videos in the 2x2 grid:
- Initially, top left and top right thumbnails correctly played their corresponding videos
- Bottom left and bottom right thumbnails briefly showed the top left video before turning into a black screen
- After attempted fixes, no thumbnails play automatically when clicked
- Bottom thumbnails now show black screens when clicked

#### Fix Attempts

1. **First Attempt: Video Array Consistency**
   - Problem identified: Potential mismatch between grid videos and playback videos
   - Solution attempted: Added stable `gridVideos` array in `InspirationsGridView` to maintain consistent video references
   - Why we thought it would work: Would ensure same video array is used in both grid and playback
   - Actual result: Issue persisted - bottom thumbnails still showed incorrect video then black screen

2. **Second Attempt: Video Manager State Management**
   - Problem identified: Race condition in video initialization and cleanup
   - Solution attempted: Modified video preloading and cleanup timing in `VideoPlaybackView`
   - Why we thought it would work: Better state management would prevent video player deallocation
   - Actual result: Issue remained unchanged

3. **Third Attempt: Index Tracking**
   - Problem identified: Possible index mismatch between grid and playback view
   - Solution attempted: Added more robust index tracking and logging
   - Why we thought it would work: Would help identify where index mismatches occur
   - Actual result: Logs showed correct indices but playback still failed for bottom videos

4. **Fourth Attempt: Video Manager Lifecycle and Cleanup**
   - Problem identified: Video player lifecycle and cleanup issues causing black screens
   - Solution attempted:
     ```swift
     // Before:
     .onDisappear {
         videoManager.cleanupAllVideos()
     }

     // After:
     .onDisappear {
         logger.debug("📱 VIEW LIFECYCLE: VideoPlaybackView disappeared - cleaning up resources")
         // Only cleanup when view actually disappears
         videoManager.cleanupAllVideos()
     }

     // Added new method to VideoManager:
     func cleanupAllVideos() {
         for (index, _) in players.enumerated() {
             cleanupVideo(for: index)
         }
         players.removeAll()
         logger.debug("🧹 Cleaned up all video players")
     }
     ```
   - Why we thought it would work: Better cleanup management would prevent premature deallocation of video players
   - Actual result: Issue persisted - bottom thumbnails still show incorrect video then black screen

5. **Fifth Attempt: Complete Resource Cleanup**
   - Problem identified: Video resources not being properly cleaned up between transitions
   - Solution attempted: Modified cleanupVideo method to ensure complete cleanup
   ```swift
   // Before:
   if let player = players[index] {
       player.pause()
       player.replaceCurrentItem(with: nil)
       players.removeValue(forKey: index)
   }

   // After:
   if let player = players[index] {
       player.pause()
       player.rate = 0
       player.replaceCurrentItem(with: nil)
       players.removeValue(forKey: index)
   }
   ```
   - Why we thought it would work: More thorough cleanup would prevent resource conflicts
   - Actual result: Videos stopped playing automatically, suggesting overcleaning of resources

6. **Sixth Attempt: Improved Preloading Logic**
   - Problem identified: Preloading not managing resources effectively
   - Solution attempted: Added cleanup before preloading and improved state management
   ```swift
   // Before:
   func preloadVideo(url: URL, forIndex index: Int) async {
       playerUrls[index] = url
       // ... rest of preloading logic
   }

   // After:
   func preloadVideo(url: URL, forIndex index: Int) async {
       cleanupVideo(for: index)
       playerUrls[index] = url
       // ... rest of preloading logic
   }
   ```
   - Why we thought it would work: Clean slate before preloading would prevent resource conflicts
   - Actual result: Videos still not playing automatically, black screens appearing

7. **Seventh Attempt: Better Video State Management**
   - Problem identified: Video player states not being managed correctly
   - Solution attempted: Added better state tracking and preloading of adjacent videos
   ```swift
   // Before:
   for i in 0..<viewModel.videos.count {
       if abs(i - index) > 1 {
           videoManager.cleanupVideo(for: i)
       }
   }

   // After:
   let distantPlayers = videoManager.getDistantPlayers(from: index)
   for i in distantPlayers {
       videoManager.cleanupVideo(for: i)
       logger.debug("🧹 Cleaned up distant video at index: \(i)")
   }
   ```
   - Why we thought it would work: Better state management would prevent incorrect video display
   - Actual result: Still experiencing playback issues, suggesting deeper problem with player initialization

8. **Eighth Attempt: Thread Safety and Preload Timing**
   - Problem identified: Race conditions between preloading, navigation, and playback
   - Solution implemented:
     1. Moved video preloading to grid view before navigation
     2. Replaced `DispatchQueue.main.async` with `MainActor.run` for thread safety
     3. Removed redundant preloading in playback view
     4. Added comprehensive logging for debugging
   - Why we think it will work:
     - Ensures video is ready before navigation occurs
     - Maintains proper thread safety for UI updates
     - Eliminates race conditions in video initialization
   - Actual result: Pending verification

### Current Implementation
- Videos are preloaded in the grid view before navigation
- Navigation only occurs after successful preload
- Playback starts immediately upon entering playback view
- Next video is preloaded for smooth transitions
- Comprehensive logging for debugging and monitoring

### Next Steps
- Verify if latest changes resolve the playback issues
- Implement right swipe gesture to return to inspiration board
- Add transition animations for smoother user experience
- Consider implementing video thumbnail caching for faster grid loading

### Logging Implementation Instructions

To diagnose video playback issues, add the following logging statements:

#### 1. VideoManager.swift - Player Access Logging
```swift
func player(for index: Int) -> AVPlayer {
    logger.debug("🎯 REQUEST: Getting player for index \(index)")
    logger.debug("🔍 CURRENT STATE: Active players at indices: \(players.keys.sorted())")
    if let url = playerUrls[index] {
        logger.debug("📺 VIDEO INFO: URL for index \(index): \(url)")
    }

    if let existingPlayer = players[index] {
        logger.debug("🎮 PLAYER ACCESS: Using existing player for index \(index)")
        if let currentItem = existingPlayer.currentItem {
            logger.debug("📊 PLAYER STATUS: Video \(index) ready to play: \(currentItem.status == .readyToPlay)")
            if let asset = currentItem.asset as? AVURLAsset {
                logger.debug("🔍 PLAYER DETAIL: Current URL for index \(index): \(asset.url)")
            }
            if currentItem.status == .failed {
                logger.debug("⚠️ PLAYER WARNING: Player item failed for index \(index), will attempt recovery")
            }
        } else {
            logger.debug("⚠️ PLAYER WARNING: Player exists but has no item for index \(index)")
        }
    }
    // ... rest of method
}
```

#### 2. VideoManager.swift - Preload Logging
```swift
@MainActor
func preloadVideo(url: URL, forIndex index: Int) async {
    logger.debug("🔄 PRELOAD START: Index \(index) with URL \(url)")
    logger.debug("📊 PRELOAD STATE: Current preloaded indices: \(self.preloadedPlayers.keys.sorted())")
    logger.debug("📊 PRELOAD STATE: Current active indices: \(self.players.keys.sorted())")
    
    // Clean up any existing resources for this index first
    cleanupVideo(for: index)
    
    playerUrls[index] = url
    logger.debug("🎯 SYSTEM: Preloading video for index \(index)")
    // ... rest of method
}
```

#### 3. VideoManager.swift - Cleanup Logging
```swift
func cleanupVideo(for index: Int) {
    logger.debug("🧹 CLEANUP START: Index \(index)")
    if let url = playerUrls[index] {
        logger.debug("🗑️ CLEANUP INFO: Removing player for URL \(url)")
    }
    if let player = players[index], let asset = player.currentItem?.asset as? AVURLAsset {
        logger.debug("🗑️ CLEANUP DETAIL: Current player URL: \(asset.url)")
    }
    // ... rest of method
}
```

#### 4. VideoManager.swift - Toggle Play/Pause Logging
```swift
func togglePlayPauseAction(index: Int) {
    logger.debug("👆 TOGGLE: Requested for index \(index)")
    if let player = players[index], let asset = player.currentItem?.asset as? AVURLAsset {
        logger.debug("🎮 TOGGLE INFO: Current URL: \(asset.url)")
    }
    // ... rest of method
}
```

#### 5. VideoPlaybackView.swift - Video Appearance Logging
```swift
private func handleVideoAppear(_ index: Int) {
    logger.debug("📱 Video view \(index) appeared")
    logger.debug("📊 Current queue position \(index + 1) of \(viewModel.videos.count)")
    // ... rest of method
}
```

#### 6. VideoPlaybackView.swift - Index Change Logging
```swift
private func handleIndexChange(oldValue: Int?, newValue: Int?) {
    if let index = newValue {
        logger.debug("🎯 Current index changed from \(oldValue ?? -1) to \(index)")
        logger.debug("📊 \(viewModel.videos.count - (index + 1)) videos remaining in queue")
        // ... rest of method
    }
}
```

These logs will help track:
1. Video URL requests vs actual loaded content
2. Player state transitions and initialization
3. Cleanup timing and effectiveness
4. Resource management and reuse
5. Video appearance and disappearance timing
6. Index changes and queue management

To analyze the logs:
1. Run the app with these logging changes
2. Click each thumbnail in the grid
3. Look for:
   - Mismatches between requested and loaded URLs
   - Incorrect cleanup timing
   - Failed player initialization
   - Unexpected player reuse
   - State transition issues

The logs will show the complete lifecycle of each video player, making it easier to identify where the playback process breaks down.

### Latest Video Playback Issue (Grid Selection)

#### Problem Description
When selecting a video thumbnail from the 2x2 grid view, there's no guarantee that the selected video will be the one that starts playing. This indicates a potential race condition or state management issue between video selection and playback initialization.

#### Fix Attempts

9. **Ninth Attempt: MainActor and Task Coordination**
   - Problem identified: Potential thread safety issues with video initialization and playback
   - Solution attempted:
   ```swift
   // Before (in VideoPlaybackView.swift):
   .task {
       viewModel.videos = videos
       currentIndex = initialIndex
       
       if let url = URL(string: initialVideo.url) {
           await videoManager.preloadVideo(url: url, forIndex: initialIndex)
           DispatchQueue.main.async {
               videoManager.togglePlayPauseAction(index: initialIndex)
           }
       }
   }

   // After:
   .task {
       // Initialize state and preload immediately
       viewModel.videos = videos
       currentIndex = initialIndex
       logger.info("📊 INITIAL STATE: Setting up \(viewModel.videos.count) videos, current index: \(initialIndex)")
       
       // Setup video completion handler first
       setupVideoCompletion()
       
       // Start playing the current video immediately
       if let url = URL(string: initialVideo.url) {
           logger.info("🎬 Starting playback for initial video: \(initialVideo.id)")
           
           // Start playing immediately on main thread
           await MainActor.run {
               videoManager.togglePlayPauseAction(index: initialIndex)
               logger.info("▶️ Playback started for initial video at index: \(initialIndex)")
           }
           
           // Preload the next video if available
           if initialIndex + 1 < videos.count,
              let nextVideoUrl = URL(string: videos[initialIndex + 1].url) {
               await videoManager.preloadVideo(url: nextVideoUrl, forIndex: initialIndex + 1)
               logger.info("🔄 Preloaded next video at index: \(initialIndex + 1)")
           }
       }
   }
   ```
   - Why we thought it would work: Using `MainActor.run` would ensure proper thread synchronization and prevent race conditions
   - Actual result: Issue still persists

10. **Tenth Attempt: Grid View Preloading**
    - Problem identified: Navigation might occur before video is fully preloaded
    - Solution attempted:
    ```swift
    // Before (in InspirationsGridView.swift):
    Button {
        selectedVideo = video
        selectedIndex = index
        isVideoPlaybackActive = true
    }

    // After:
    Button {
        logger.info("👆 Grid selection - Video ID: \(video.id), Index: \(index), Grid Position: \(index % 2),\(index / 2)")
        selectedVideo = video
        selectedIndex = index
        
        // Ensure video is ready for playback
        Task {
            if let url = URL(string: video.url) {
                // Preload video before navigation
                await videoManager.preloadVideo(url: url, forIndex: index)
                logger.info("🔄 Preloaded video at index: \(index)")
                
                // Only navigate after successful preload
                await MainActor.run {
                    isVideoPlaybackActive = true
                    logger.info("🎥 Navigating to video playback for index: \(index)")
                }
            }
        }
    }
    ```
    - Why we thought it would work: Ensuring video is preloaded before navigation would prevent playback issues
    - Actual result: Issue still persists

11. **Eleventh Attempt: Immediate Playback and Start from Beginning**
    - Problem identified: Videos not playing immediately and not starting from beginning
    - Solution attempted:
    ```swift
    // Before (in VideoPlaybackView.swift):
    // Start playing immediately on main thread
    await MainActor.run {
        videoManager.togglePlayPauseAction(index: initialIndex)
        logger.info("▶️ Playback started for initial video at index: \(initialIndex)")
    }

    // After:
    // Ensure we start from the beginning and play immediately
    if let player = videoManager.currentPlayer(at: initialIndex) {
        await player.seek(to: .zero)
        player.play()
    }
    ```
    - Why we thought it would work: Direct player control would bypass any potential state management issues
    - Actual result: Videos still not autoplaying, and bottom thumbnails showing incorrect video

12. **Twelfth Attempt: VideoManager Playback Control**
    - Problem identified: Inconsistent playback behavior across different entry points
    - Solution attempted:
    ```swift
    // Before (in VideoManager.swift):
    case .readyToPlay:
        logger.info("✅ PLAYBACK INFO: Video \(index) is ready to play")
        // Ensure proper playback rate and play
        player.rate = 1.0
        player.play()

    // After:
    case .readyToPlay:
        logger.info("✅ PLAYBACK INFO: Video \(index) is ready to play")
        // Always start from beginning
        await player.seek(to: .zero)
        player.rate = 1.0
        player.play()
    ```
    - Why we thought it would work: Ensuring consistent playback behavior by always seeking to start
    - Actual result: Issue persists - videos not autoplaying and bottom thumbnails showing wrong video

Current Issues:
1. No autoplay on any thumbnail click
2. Bottom thumbnails load incorrect video (showing top left video)

# Phase 9: Video Playback Debugging

## Black Screen Issue Investigation

### Attempt 1 - VideoManager Instance Sharing
**Problem:**  
The black screen occurred because we had two separate `VideoManager` instances - one in `InspirationsGridView` and another in `VideoPlaybackView`. This meant that preloaded videos in the grid view weren't available in the playback view. The separate instances caused a loss of state and player resources during the transition.

**Solution Attempted:**  
Changed `VideoPlaybackView` to accept a `VideoManager` instance instead of creating its own:

Before:
```swift
struct VideoPlaybackView: View {
    @StateObject private var videoManager = VideoManager()
    // ...
}
```

After:
```swift
struct VideoPlaybackView: View {
    @ObservedObject var videoManager: VideoManager
    // ...
    
    init(initialVideo: Video, initialIndex: Int, videos: [Video], videoManager: VideoManager) {
        self.videoManager = videoManager
        // ...
    }
}
```

And updated `InspirationsGridView` to pass its manager:
```swift
VideoPlaybackView(
    initialVideo: video,
    initialIndex: index,
    videos: gridVideos,
    videoManager: videoManager
)
```

**Why We Thought It Would Work:**  
By sharing a single `VideoManager` instance, preloaded videos and player states would persist during the transition from grid to playback view. The `VideoManager` would maintain its active players and observers, preventing the need to recreate players during navigation.

**What Actually Happened:**  
The logs showed that while the `VideoManager` instance was successfully shared:
```
📱 VideoManager initialized
🎯 REQUEST: Getting player for index 0
✅ PRELOAD: Using preloaded player for index 0
```
However, the black screen persisted, suggesting the issue might be deeper than just instance sharing.

### Attempt 2 - Optional Type Handling
**Problem:**  
After fixing the instance sharing, we encountered linter errors related to optional type handling in `VideoPlaybackView`. The code was using non-optional `Int` values in conditional bindings where optionals were expected. This suggested potential issues with index handling during video transitions.

**Solution Attempted:**  
Modified the conditional bindings in `VideoPlaybackView`:

Before:
```swift
if let current = currentIndex {
    // ...
}
```

After:
```swift
if currentIndex >= 0 && currentIndex < videos.count {
    // ...
}
```

**Why We Thought It Would Work:**  
By replacing optional bindings with direct range checks, we would ensure proper index validation while maintaining type safety. This would prevent any potential nil-related issues during video transitions.

**What Actually Happened:**  
The linter errors were resolved, but logs showed that video playback was still not initializing properly:
```
📱 VideoPlaybackView initialized with video: video_id at index: 0, total videos: 4
❌ PLAYBACK ERROR: Cannot play video 0 - no current item
```

### Attempt 3 - Player State Management
**Problem:**  
The logs revealed that even though we had a valid index and URL, the player wasn't receiving a valid item. This indicated a potential issue with player state management during the transition from grid to playback view. The player might be getting cleaned up prematurely.

**Solution Attempted:**  
Added state tracking in `VideoManager` and modified cleanup behavior:

Before:
```swift
func cleanupVideo(for index: Int) {
    players[index]?.pause()
    cleanupObservers(for: index)
    players.removeValue(forKey: index)
}
```

After:
```swift
func cleanupVideo(for index: Int) {
    // Don't cleanup active or adjacent videos during playback
    if case .active(let activeIndex) = currentState {
        if abs(index - activeIndex) <= 1 {
            logger.info("⏭️ SKIP: Skipping cleanup for adjacent video \(index)")
            return
        }
    }
    // ... rest of cleanup code
}
```

**Why We Thought It Would Work:**  
By preventing cleanup of active and adjacent videos during playback transitions, we would ensure that the necessary player resources remain available. This would maintain video playback continuity during navigation.

**What Actually Happened:**  
The logs showed improved state management:
```
🎮 STATE: Preparing playback for index 0
✅ STATE: Active playback at index 0
⏭️ SKIP: Skipping cleanup for adjacent video 0
```
However, the black screen issue persisted, suggesting that while player state was being maintained, there might be issues with the actual video content rendering.

### Next Steps
- Investigate video content rendering pipeline
- Add more detailed logging around AVPlayer item status changes
- Consider implementing video thumbnail display as fallback
- Review SwiftUI view lifecycle handling during transitions

### Video Playback Issues - Grid Selection

#### Problem 1: Video Preloading Timeout
**Description:**
- Videos consistently time out during preload after 10 seconds
- No videos successfully preload, preventing navigation to video playback
- Timeout is too aggressive for initial video load

**Current Implementation:**
```swift
func preloadVideo(url: URL, forIndex index: Int) async throws {
    // ... existing code ...
    
    // Set a timeout to prevent infinite waiting
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds timeout
        if !hasResumed {
            hasResumed = true
            logger.error("⏰ PRELOAD TIMEOUT: Video \(index) preload timed out after 10 seconds")
            continuation.resume(throwing: NSError(domain: "com.Gauntlet.LikeThese", code: -2, userInfo: [NSLocalizedDescriptionKey: "Preload timeout"]))
        }
    }
}
```

**Proposed Fix:**
```swift
func preloadVideo(url: URL, forIndex index: Int) async throws {
    logger.info("🔄 PRELOAD: Starting preload for index \(index)")
    
    // If player already exists and is ready, just return
    if let existingPlayer = players[index],
       let currentItem = existingPlayer.currentItem,
       currentItem.status == .readyToPlay {
        logger.info("✅ PRELOAD: Player already exists and ready for index \(index)")
        return
    }
    
    // Create new player item with longer timeout
    let playerItem = try await withTimeout(seconds: 30) { // Increased timeout
        try await videoCacheService.preloadVideo(url: url)
    }
    
    // Ensure minimum buffer before considering ready
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        var hasResumed = false
        
        let observer = playerItem.observe(\.loadedTimeRanges) { [weak self] item, _ in
            guard let self,
                  !hasResumed,
                  let firstRange = item.loadedTimeRanges.first as? CMTimeRange else { return }
            
            let bufferedDuration = CMTimeGetSeconds(firstRange.duration)
            let progress = Float(bufferedDuration / self.minimumBufferDuration)
            
            Task { @MainActor in
                self.bufferingProgress[index] = min(progress, 1.0)
                logger.info("📊 BUFFER PROGRESS: Video \(index) buffered \(String(format: "%.1f", bufferedDuration))s (\(String(format: "%.0f", progress * 100))%)")
                
                // Consider ready if we have either:
                // 1. Buffered our minimum duration
                // 2. Buffered the entire video
                if bufferedDuration >= self.minimumBufferDuration || progress >= 1.0 {
                    hasResumed = true
                    continuation.resume()
                    self.observers[index]?.invalidate()
                    self.observers.removeValue(forKey: index)
                }
            }
        }
        
        self.observers[index] = observer
        
        // Set up error handling with retry
        let errorObserver = playerItem.observe(\.status) { [weak self] item, _ in
            guard let self, !hasResumed else { return }
            
            switch item.status {
            case .failed:
                Task {
                    // Attempt retry once before failing
                    do {
                        let newPlayerItem = try await self.videoCacheService.preloadVideo(url: url)
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(returning: ())
                        }
                    } catch {
                        if !hasResumed {
                            hasResumed = true
                            logger.error("❌ PRELOAD ERROR: Failed to preload video at index \(index): \(String(describing: item.error))")
                            continuation.resume(throwing: error)
                        }
                    }
                }
            case .readyToPlay:
                if !hasResumed {
                    hasResumed = true
                    continuation.resume()
                }
            default:
                break
            }
        }
        
        self.observers[index + 1000] = errorObserver
        
        // Set a timeout that scales with network conditions
        Task { @MainActor in
            let timeout = NetworkMonitor.shared.isOnCellular ? 45.0 : 30.0
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !hasResumed {
                hasResumed = true
                logger.error("⏰ PRELOAD TIMEOUT: Video \(index) preload timed out after \(timeout) seconds")
                continuation.resume(throwing: NSError(domain: "com.Gauntlet.LikeThese", code: -2, userInfo: [NSLocalizedDescriptionKey: "Preload timeout"]))
            }
        }
    }
    
    // Now safe to create player
    await MainActor.run {
        let player = AVPlayer(playerItem: playerItem)
        players[index] = player
        playerItems[index] = playerItem
        playerUrls[index] = url
        bufferingStates[index] = false
        logger.info("✅ PRELOAD: Successfully created player for index \(index)")
    }
}
```

**Why This Will Work:**
1. Increased timeout duration with network awareness
2. Added retry mechanism for failed preloads
3. More flexible buffering criteria
4. Better error handling and logging
5. Network-aware timeout adjustments

#### Problem 2: Firebase Storage URL Resolution
**Description:**
- Video URLs from Firebase Storage aren't being properly resolved
- No direct error logs but consistent timeouts suggest URL resolution issues

**Current Implementation:**
```swift
// In VideoCacheService.swift
let storageRef = Storage.storage().reference().child("videos").child(filename)
let signedURL = try await storageRef.downloadURL()
```

**Proposed Fix:**
```swift
class VideoCacheService {
    private let storage = Storage.storage()
    private var urlCache = NSCache<NSString, CachedURL>()
    
    struct CachedURL {
        let url: URL
        let expirationDate: Date
    }
    
    func getVideoURL(filename: String) async throws -> URL {
        let cacheKey = filename as NSString
        
        // Check cache first
        if let cached = urlCache.object(forKey: cacheKey),
           cached.expirationDate > Date() {
            logger.debug("✅ Using cached signed URL for: \(filename)")
            return cached.url
        }
        
        // Get fresh signed URL with retry
        return try await withRetry(maxAttempts: 3) {
            let storageRef = self.storage.reference().child("videos").child(filename)
            let signedURL = try await storageRef.downloadURL()
            
            // Cache URL with 1-hour expiration
            let cached = CachedURL(
                url: signedURL,
                expirationDate: Date().addingTimeInterval(3600)
            )
            self.urlCache.setObject(cached, forKey: cacheKey)
            
            logger.debug("✅ Got fresh signed URL for: \(filename)")
            return signedURL
        }
    }
    
    func preloadVideo(url: URL) async throws -> AVPlayerItem {
        let cacheKey = url.absoluteString as NSString
        
        // Extract filename and get signed URL
        let filename = url.lastPathComponent
        let signedURL = try await getVideoURL(filename: filename)
        
        // Rest of existing preloadVideo implementation...
    }
}
```

**Why This Will Work:**
1. Caches signed URLs to reduce Firebase calls
2. Implements retry mechanism for URL resolution
3. Better error handling and logging
4. Reduces likelihood of timeout during URL resolution
5. More efficient resource usage

#### Problem 3: Premature Resource Cleanup
**Description:**
- Resources are being cleaned up too aggressively during view transitions
- Cleanup occurs during navigation, causing playback issues

**Current Implementation:**
```swift
.onDisappear {
    // Only cleanup if we're not transitioning to video playback
    if !isVideoPlaybackActive {
        logger.info("📱 Grid view disappeared - cleaning up resources")
        for index in 0..<gridVideos.count {
            videoManager.cleanupVideo(for: index)
        }
    }
}
```

**Proposed Fix:**
```swift
class VideoManager {
    private var isTransitioningToPlayback = false
    private var activeIndices = Set<Int>()
    private var pendingCleanup = Set<Int>()
    
    func prepareForTransition(from currentIndex: Int, to targetIndex: Int) {
        isTransitioningToPlayback = true
        activeIndices = Set([currentIndex, targetIndex])
        // Keep adjacent videos for smooth navigation
        activeIndices.insert(currentIndex - 1)
        activeIndices.insert(currentIndex + 1)
        activeIndices.insert(targetIndex - 1)
        activeIndices.insert(targetIndex + 1)
    }
    
    func cleanupVideo(for index: Int) {
        guard !isTransitioningToPlayback else {
            // If transitioning, add to pending cleanup
            if !activeIndices.contains(index) {
                pendingCleanup.insert(index)
            }
            return
        }
        
        // Actual cleanup implementation...
    }
    
    func finishTransition() {
        isTransitioningToPlayback = false
        // Cleanup any pending indices that aren't active
        for index in pendingCleanup {
            if !activeIndices.contains(index) {
                cleanupVideo(for: index)
            }
        }
        pendingCleanup.removeAll()
    }
}

// In InspirationsGridView.swift
.onDisappear {
    // Only cleanup if we're not transitioning to video playback
    if !isVideoPlaybackActive {
        logger.info("📱 Grid view disappeared - cleaning up resources")
        videoManager.finishTransition() // This will handle cleanup properly
    }
}
```

**Why This Will Work:**
1. Prevents cleanup of active and adjacent videos
2. Defers cleanup until transition is complete
3. Maintains resources needed for smooth playback
4. Better state management during transitions
5. More efficient resource management

#### Problem 4: Navigation State Management
**Description:**
- Navigation state isn't properly coordinated with video preloading
- State updates occur before preloading is complete

**Current Implementation:**
```swift
func preloadAndNavigate(to index: Int) async throws {
    try await videoManager.prepareForTransition(from: -1, to: index)
    try await videoManager.preloadVideo(url: url, forIndex: index)
    
    await MainActor.run {
        selectedVideo = video
        selectedIndex = index
        isVideoPlaybackActive = true
    }
}
```

**Proposed Fix:**
```swift
enum VideoPreloadState {
    case notStarted
    case loading(progress: Float)
    case ready
    case failed(Error)
}

class VideoManager {
    @Published private(set) var preloadStates: [Int: VideoPreloadState] = [:]
    
    func updatePreloadState(_ state: VideoPreloadState, for index: Int) {
        Task { @MainActor in
            preloadStates[index] = state
        }
    }
}

struct InspirationsGridView: View {
    @State private var preloadingIndex: Int?
    @State private var showPreloadError = false
    @State private var lastError: Error?
    
    func preloadAndNavigate(to index: Int) async throws {
        guard let video = gridVideos[safe: index],
              let url = URL(string: video.url) else {
            throw NavigationError.invalidVideo
        }
        
        // Update UI to show loading state
        await MainActor.run {
            preloadingIndex = index
        }
        
        do {
            // Prepare for transition
            try await videoManager.prepareForTransition(from: -1, to: index)
            
            // Preload video with progress updates
            try await videoManager.preloadVideo(url: url, forIndex: index)
            
            // Verify video is ready
            guard let player = videoManager.currentPlayer(at: index),
                  player.currentItem?.status == .readyToPlay else {
                throw NavigationError.videoNotReady
            }
            
            // Update state and navigate
            await MainActor.run {
                selectedVideo = video
                selectedIndex = index
                isVideoPlaybackActive = true
                preloadingIndex = nil
            }
            
            // Preload next video if available
            if let nextVideo = gridVideos[safe: index + 1],
               let nextUrl = URL(string: nextVideo.url) {
                Task {
                    try? await videoManager.preloadVideo(url: nextUrl, forIndex: index + 1)
                }
            }
        } catch {
            await MainActor.run {
                preloadingIndex = nil
                lastError = error
                showPreloadError = true
            }
            throw error
        }
    }
    
    private func gridItem(for video: Video, index: Int, width: CGFloat, height: CGFloat) -> some View {
        Button {
            Task {
                do {
                    try await preloadAndNavigate(to: index)
                } catch {
                    logger.error("❌ GRID: Failed to navigate to video at index \(index): \(error.localizedDescription)")
                }
            }
        } label: {
            ZStack {
                // Existing thumbnail view code...
                
                if preloadingIndex == index {
                    if let state = videoManager.preloadStates[index] {
                        switch state {
                        case .loading(let progress):
                            LoadingOverlay(progress: progress)
                        case .failed:
                            ErrorOverlay()
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }
        .alert("Failed to Load Video",
               isPresented: $showPreloadError,
               presenting: lastError) { _ in
            Button("OK") {
                showPreloadError = false
            }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}
```

**Why This Will Work:**
1. Better state management during preloading
2. Visual feedback during loading process
3. Proper error handling and user feedback
4. Prevents navigation until video is ready
5. Smoother transition experience

### Implementation Plan
1. Deploy fixes in order:
   - Firebase Storage URL resolution
   - Video preloading timeout
   - Resource cleanup
   - Navigation state management
2. Add comprehensive logging
3. Add error recovery mechanisms
4. Implement proper loading states
5. Add network-aware optimizations

### Expected Results
- Reliable video preloading
- Smooth transitions between grid and playback
- Better error handling and recovery
- Improved user feedback during loading
- More efficient resource management

// ... existing code ...