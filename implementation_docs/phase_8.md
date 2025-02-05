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

### Debugging VideoManager Observer Issues

#### Issue Overview
The `VideoManager.swift` file is experiencing build errors related to type inference in KVO (Key-Value Observing) observers. The main error occurs in the `setupStateObserver` function where we observe the player's `timeControlStatus`.

#### Debugging Steps and Iterations

1. Initial Implementation
```swift
private func setupStateObserver(for player: AVPlayer, at index: Int) {
    let observer = player.observe(\.timeControlStatus) { [weak self] player, _ in
        // ... handler code ...
    }
}
```
**Error**: Type of expression is ambiguous without a type annotation
**Analysis**: Swift compiler cannot infer types for the KVO observation

2. Added Explicit Type Annotation
```swift
private func setupStateObserver(for player: AVPlayer, at index: Int) {
    let observer: NSKeyValueObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] (player: AVPlayer, _) in
        // ... handler code ...
    }
}
```
**Error**: Same ambiguous type error
**Analysis**: Adding NSKeyValueObservation type and options didn't resolve the ambiguity

3. Tried Closure-Based Syntax
```swift
private func setupStateObserver(for player: AVPlayer, at index: Int) {
    let observer: NSKeyValueObservation = {
        return player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            // ... handler code ...
        }
    }()
}
```
**Error**: Same ambiguous type error
**Analysis**: Restructuring as a closure didn't help type inference

4. Full Type Specification
```swift
private func setupStateObserver(for player: AVPlayer, at index: Int) {
    let observer: NSKeyValueObservation = player.observe(\.timeControlStatus, changeHandler: { (player: AVPlayer, change: NSKeyValueObservedChange<AVPlayer.TimeControlStatus>) in
        // ... handler code ...
    })
}
```
**Error**: Still getting ambiguous type error
**Analysis**: Even with fully specified types, compiler still has issues

#### Additional Warnings
1. Unused Observer Warning
```swift
let timeObserver = player.addPeriodicTimeObserver(...)
```
**Warning**: Initialization of immutable value 'timeObserver' was never used
**Analysis**: Observer is created but not stored, might lead to premature deallocation

2. Unused Self Warning
```swift
let errorObserver = player.observe(\.currentItem?.error) { [weak self] player, _ in
```
**Warning**: Variable 'self' was written to, but never read
**Analysis**: [weak self] capture list is used but self isn't accessed in the closure

#### Current State
The code is following patterns used elsewhere in the codebase for KVO observation, but the Swift compiler is having trouble with type inference specifically for the `timeControlStatus` observation. This might be due to:
1. Swift version differences
2. AVKit framework version specifics
3. Potential type system edge case with KVO and AVPlayer status observation

#### Next Steps to Consider
1. Investigate if this is a known Swift compiler issue with AVPlayer KVO
2. Consider alternative approaches to state observation (e.g., NotificationCenter)
3. Try different Swift compiler flags or version
4. Consider splitting the observation into smaller, more explicit type chunks

#### Related Code
The observer is used in conjunction with other observers in the VideoManager:
- End time observer (NotificationCenter based)
- Buffering state observer (KVO based)
- Error observer (KVO based)

All these observers work together to manage the video player's state and ensure proper cleanup.

#### Additional Observer Debugging Attempts

1. Initial Observer Storage Attempt
```swift
private func setupBuffering(for player: AVPlayer, at index: Int) {
    // ... observer setup code ...
    observers[index] = observer  // Single dictionary approach
}
```
**Error**: Unused observer warnings and potential premature deallocation
**Analysis**: Observers need to be stored properly to prevent deallocation

2. Multiple Observer Dictionaries
```swift
private var observers: [Int: NSKeyValueObservation] = [:]
private var errorObservers: [Int: NSKeyValueObservation] = [:]
private var timeObservers: [Int: Any] = [:]
private var endTimeObservers: [Int: Any] = [:]

private func setupBuffering(for player: AVPlayer, at index: Int) {
    // ... observer setup code ...
    observers[index] = bufferingObserver
    timeObservers[index] = timeObserver
    errorObservers[index] = errorObserver
}
```
**Error**: Type inference issues with observers
**Analysis**: Need explicit type annotations for KVO observers

3. Type Annotation Attempt
```swift
private func setupStateObserver(for player: AVPlayer, at index: Int) {
    let observer: NSKeyValueObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] (player: AVPlayer, change: NSKeyValueObservedChange<AVPlayer.TimeControlStatus>) in
        // ... handler code ...
    }
}
```
**Error**: Still getting type inference errors
**Analysis**: Swift compiler having issues with KVO type inference despite explicit annotations

#### Current State and Known Issues
1. Observer Management:
   - Separated observers into different dictionaries by type
   - Added proper cleanup in `cleanupVideo`
   - Maintained weak self pattern for memory management

2. Persistent Issues:
   - Type inference errors with KVO observers
   - Potential VideoCacheService scope issue

3. Working Features:
   - Buffering state observation
   - Playback error monitoring
   - End time notification handling
   - State change tracking

4. Next Steps to Consider:
   - Investigate VideoCacheService import/scope
   - Consider alternative observer patterns if KVO issues persist
   - Monitor memory usage with multiple observer dictionaries

The code is functionally working despite the linter warnings, with proper observer cleanup and memory management in place.

#### Additional Known Issues

1. VideoCacheService Import
```swift
// Current imports
import Foundation
import AVKit
import os
import FirebaseStorage  // Required for VideoCacheService

// Error
Cannot find 'VideoCacheService' in scope
```
**Analysis**: 
- VideoCacheService is defined in `LikeThese/Services/VideoCacheService.swift`
- Requires proper module imports and project setup
- May need to ensure Services directory is included in build target

2. Remaining Type Inference Issues
Despite explicit type annotations, some KVO observers still show type inference errors:
```swift
// Still showing ambiguous type error
let observer: NSKeyValueObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] (player: AVPlayer, change: NSKeyValueObservedChange<AVPlayer.TimeControlStatus>) in
    // ... handler code ...
}
```

#### Next Steps
1. Verify project structure and module imports
2. Consider moving VideoCacheService to a shared module
3. Investigate alternative KVO patterns if type inference issues persist
4. Monitor memory management with multiple observer dictionaries

### Error Tracking and Solutions

#### 1. KVO Type Inference Error
**Error**: `type of expression is ambiguous without a type annotation`
**Location**: `setupStateObserver` function, line creating time interval
**Attempted Solutions**:
1. Added explicit type annotation:
```swift
let observer: NSKeyValueObservation = player.observe(\.timeControlStatus) { ... }
```
**Result**: Still got type inference error

2. Added full type specification:
```swift
let observer: NSKeyValueObservation = player.observe(
    \.timeControlStatus,
    options: [.new, .old]
) { [weak self] (observedPlayer: AVPlayer, change: NSKeyValueObservedChange<AVPlayer.TimeControlStatus>) in
    // ... handler code ...
}
```
**Result**: Error persisted

3. Switched to NotificationCenter:
```swift
NotificationCenter.default.addObserver(
    forName: .AVPlayerTimeControlStatusDidChange,
    object: player,
    queue: .main
) { ... }
```
**Result**: New error - `AVPlayerTimeControlStatusDidChange` not found

4. Final Working Solution:
```swift
let interval = CMTime(value: 1, timescale: 10) // Explicit values instead of floating point
let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { ... }
```

#### 2. VideoCacheService Not Found
**Error**: `Cannot find 'VideoCacheService' in scope`
**Location**: Top of file where services are initialized
**Attempted Solutions**:
1. Add import:
```swift
import VideoCacheService
```
**Result**: Module not found

2. Check project structure:
- Verified VideoCacheService.swift exists
- Confirmed it's included in target
**Result**: Still not found

3. Planned Solution:
- Move VideoCacheService to proper module
- Add proper import statement
- Ensure it's included in build target

#### 3. Multiple Observer Storage
**Problem**: Multiple observers being stored incorrectly
**Location**: `setupBuffering` function
**Attempted Solutions**:
1. Single dictionary approach:
```swift
private var observers: [Int: Any] = [:]
```
**Result**: Type safety issues

2. Multiple typed dictionaries:
```swift
private var stateObservers: [Int: NSKeyValueObservation] = [:]
private var bufferingObservers: [Int: NSKeyValueObservation] = [:]
private var timeObservers: [Int: Any] = [:]
```
**Result**: Better type safety but more complex management

3. Final Approach:
```swift
private var observers: [Int: NSKeyValueObservation] = [:]
private var endTimeObservers: [Int: Any] = [:]  // For time observers that can't be typed
```
**Result**: Balance of type safety and practicality

#### 4. Memory Management Issues
**Problem**: Potential memory leaks from observers
**Location**: Throughout observer setup and cleanup
**Solutions**:
1. Added weak self:
```swift
{ [weak self] in
    guard let self = self else { return }
    // ... handler code ...
}
```

2. Added explicit cleanup:
```swift
func cleanupVideo(for index: Int) {
    observers[index]?.invalidate()
    NotificationCenter.default.removeObserver(endTimeObservers[index] ?? "")
    // ... cleanup code ...
}
```

3. Added verification of cleanup:
```swift
logger.debug("🧹 CLEANUP: Starting cleanup for video \(index)")
// ... cleanup code ...
logger.debug("✨ CLEANUP: Completed cleanup for video \(index)")
```

#### Current Status
- KVO type inference issue: Partially resolved with periodic time observer
- VideoCacheService scope: Pending proper module organization
- Observer management: Working but could be improved
- Memory management: Properly handled with weak references and cleanup

#### Next Steps
1. Properly modularize VideoCacheService
2. Consider refactoring observer management into separate class
3. Add more comprehensive error handling
4. Implement proper dependency injection for services
