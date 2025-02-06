## Phase 9: Inspirations Board
### Checklist
- [x] Implement a 2x2 grid view for recommended videos. This will be the new "homepage" after a user logs in. The 4 videos it loads can be random for now. 
- [x] When I press on one of the videos in the 2x2 grid view for recommended videos, it should go to that video and play it.
- [ ] Make it so that when a video is playing, I can swipe to the right and it will go back to the inspiration board (the 2x2 grid view).

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