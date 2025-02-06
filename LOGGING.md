# LikeThese Logging System

## Overview
The LikeThese app uses a comprehensive logging system built on Apple's unified logging system. Each component has a dedicated logger with specific subsystem and category:

```swift
private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "ComponentName")
```

## Log Categories and Emojis

### View Lifecycle (📱)
- View initialization and appearance
- Component mounting/unmounting
- Layout updates
```swift
logger.debug("📱 VIEW LIFECYCLE: VideoPlaybackView initialized")
logger.debug("📱 VIEW LIFECYCLE: Video view \(index) appeared")
```

### Loading States (⌛️)
- Content loading progress
- Resource initialization
- Queue management
```swift
logger.debug("⌛️ LOADING STATE: Initial videos loading")
logger.debug("⌛️ LOADING STATE: Loading more videos at end of queue")
```

### User Actions (👤)
- Play/Pause interactions
- Swipe gestures with metrics
- Manual navigation
```swift
logger.debug("👤 USER ACTION: Manual pause requested for video \(index)")
logger.debug("👤 USER ACTION: Dragging with offset \(dragOffset)")
```

### System Operations (🔄)
- State management
- Resource handling
- Cleanup operations
```swift
logger.debug("🔄 SYSTEM: Preloading video for index \(index)")
logger.debug("🔄 SYSTEM: Setting up video completion handler")
```

### Network Status (🌐)
- Connectivity changes
- Download progress
- Retry operations
```swift
logger.debug("🌐 NETWORK: Connection restored")
logger.debug("🌐 NETWORK: No connection, queueing video \(index) for later")
```

### Playback Status (🎮)
- Player state changes
- Buffering updates
- Video transitions
```swift
logger.debug("🎮 PLAYER STATE: Video \(index) state changed: \(oldState) -> \(newState)")
```

### Performance Metrics (📊)
- Buffer progress
- Playback statistics
- Queue position
```swift
logger.debug("📊 BUFFER PROGRESS: Video \(index) buffered \(String(format: "%.1f", bufferedDuration))s")
logger.debug("📊 USER STATS: Video \(index) paused at \(String(format: "%.1f", currentTime))s")
```

### Resource Management (🧹)
- Memory cleanup
- Observer removal
- Cache management
```swift
logger.debug("🧹 CLEANUP: Starting cleanup for video \(index)")
logger.debug("🧹 CLEANUP: Removed all observers for index \(index)")
```

### Success Events (✅)
- Operation completion
- State transitions
- Resource loading
```swift
logger.debug("✅ SYSTEM: Successfully preloaded video for index \(index)")
logger.debug("✅ PLAYBACK SUCCESS: Video \(index) successfully started playing")
```

### Errors and Warnings (❌/⚠️)
- Operation failures
- Resource issues
- Recovery attempts
```swift
logger.error("❌ PLAYBACK ERROR: Video \(index) failed to load: \(error.localizedDescription)")
logger.debug("⚠️ GESTURE STATE: Active gesture detected, cancelling auto-advance")
```

### Gesture Tracking (🖐️)
- Touch events
- Swipe metrics
- Gesture states
```swift
logger.debug("🖐️ Drag gesture active")
logger.debug("🖐️ Drag gesture ended")
```

### Automated Actions (🤖)
- Auto-advance
- System-initiated events
- Background tasks
```swift
logger.debug("🤖 AUTO ACTION: Video \(index) finished playing")
logger.debug("🤖 AUTO ACTION: Auto-advancing to video \(nextIndex)")
```

## Log Format
```
{timestamp} {app}[{process}] {emoji} {CATEGORY}: {message}
```

Example:
```
2024-02-05 10:15:23.456 LikeThese[12345] 👤 USER ACTION: Manual swipe up to next video from index 2
```

## Implementation Details

### VideoManager Logging
- Comprehensive player state tracking
- Buffering progress monitoring
- Resource lifecycle logging
- Error handling and recovery

### VideoPlaybackView Logging
- User interaction tracking
- Gesture metrics
- View lifecycle events
- Queue management

### Performance Monitoring
- Buffer progress tracking
- Network state monitoring
- Memory usage patterns
- Loading time metrics

## Best Practices
1. Always include context (video index, state, etc.)
2. Use appropriate emoji categories
3. Log both start and completion of operations
4. Include relevant metrics when available
5. Keep messages concise but informative
6. Use appropriate log levels (debug/error)

## Log Levels

### Debug
Used for general flow information and non-critical events
```swift
logger.debug("📱 VIEW LIFECYCLE: Video view \(index) appeared")
```

### Error
Used for operation failures and critical issues
```swift
2025-02-05 11:52:13.441 LikeThese[87814:41473712] 🎮 PLAYER STATE: Video 2 state changed: paused -> playing
```
Components:
- **Date**: 2025-02-05
- **Time**: 11:52:13.441
- **App**: LikeThese
- **Process**: 87814
- **Thread**: 41473712
- **Category Emoji**: 🎮
- **Category**: PLAYER STATE
- **Description**: Video 2 state changed: paused -> playing

## Log Levels

### Debug
- General flow information
- State transitions
- Non-critical events
- Development details

### Info
- Important state changes
- User interactions
- System events
- Operation completion

### Warning
- Non-critical issues
- Performance concerns
- Resource warnings
- Potential problems

### Error
- Operation failures
- Resource errors
- State conflicts
- User-facing issues

### Critical
- System failures
- Data corruption
- Security issues
- Fatal errors

## Best Practices

### Logging Guidelines
1. Use consistent emoji prefixes
2. Include context (index numbers, states)
3. Log operation start and completion
4. Include error details and recovery steps
5. Track state transitions
6. Monitor performance metrics
7. Log user interactions
8. Track system state changes

### Known Issues and Build Errors

1. **Linter Warnings** (Can be ignored)
```
Cannot find 'LoggingSystem' in scope
Cannot find 'Metadata' in scope
```
These linter warnings appear but don't affect functionality as long as the code compiles.

2. **Build Errors** (Must be fixed)
```
❌ underlying Objective-C module 'LikeThese' not found
@_exported import struct LikeThese.LoggingSystem
```
Do not use `@_exported import struct` statements - they will cause build failures. Instead:
- Use the types directly since they're in the same module
- If needed, use regular `import` statements
- Keep the module structure flat to avoid circular dependencies

**Affected files:**
- `VideoPlaybackView.swift`
- `VideoPlayerView.swift`
- Any file using the enhanced logging system

**Verification steps:**
1. Code compiles successfully without `@_exported` imports
2. Logging works as expected at runtime
3. All log levels and categories function correctly
4. Metadata is properly captured and formatted

**Do not:**
- Use `@_exported import` statements (causes build failures)
- Move files to different modules (breaks existing module structure)
- Change access levels of types (already properly public)
- Add unnecessary type annotations (complicates code)

## Log Analysis

### Common Patterns
1. User interaction flows
2. Error cascades
3. Performance bottlenecks
4. Resource usage patterns

### Troubleshooting
1. Check timestamp sequences
2. Follow state transitions
3. Track resource lifecycle
4. Monitor error patterns

## Implementation Examples

### View Lifecycle
```swift
logger.debug("📱 VIEW LIFECYCLE: VideoPlaybackView initialized")
```

### User Actions
```swift
logger.debug("👤 USER ACTION: Manual swipe up to next video from index \(index)")
```

### Error Handling
```swift
logger.error("❌ PLAYBACK ERROR: Video \(index) failed to load: \(error.localizedDescription)")
```

### State Changes
```swift
logger.debug("🎮 PLAYER STATE: Video \(index) state changed: \(oldState) -> \(newState)")
```

## Log Management

### Retention
- Debug logs: 7 days
- Info logs: 30 days
- Warning/Error logs: 90 days
- Critical logs: 1 year

### Storage
- Local device storage
- System console
- Remote logging service (if implemented)

### Access
- Development console
- Debug builds
- Release builds (filtered)
- Production monitoring 

### Known False Positive Linting Issues

The following linting errors appear in files using our `LoggingSystem` but can be safely ignored:

```
Cannot find 'LoggingSystem' in scope
Cannot find 'Metadata' in scope
```

**Why these are false positives:**
1. `LoggingSystem` and `Metadata` are properly defined as `public` types in `LoggingSystem.swift`
2. The code compiles and runs correctly despite these warnings
3. The types are accessible within the module without explicit imports
4. Similar type inference issues have been seen before with Swift's type system
5. This is a known issue documented in `phase_8.md` related to module structure

**Affected files:**
- `VideoPlaybackView.swift`
- `VideoPlayerView.swift`
- Any file using the enhanced logging system

**Verification steps:**
1. Code compiles successfully
2. Logging works as expected at runtime
3. All log levels and categories function correctly
4. Metadata is properly captured and formatted
5. Log output matches the expected format in the documentation

**Do not attempt to fix by:**
- Adding `@_exported import` statements (may cause circular dependencies)
- Moving files to different modules (breaks existing module structure)
- Changing access levels of types (already properly public)
- Adding unnecessary type annotations (complicates code without benefit)
- Restructuring the module (current structure is intentional)

These "fixes" may introduce actual issues or make the code more complex without resolving the underlying linter limitation. 

### Viewing Logs in the Terminal
To display your app's logs for the past 5 minutes while running in the iOS simulator, use:
```bash
xcrun simctl spawn booted log show --predicate 'process contains "LikeThese"' --debug --info --last 5m
```
Adjust the duration (`--last 5m`) or the predicate as needed to see more logs or focus on a specific timeframe.

### Live-Streaming Logs
Use this to see real-time output from the **LikeThese** simulator process:
```bash
xcrun simctl spawn booted log stream --predicate 'process contains "LikeThese"' --debug --info
```
To see historical logs for the past 5 minutes:
```bash
xcrun simctl spawn booted log show --predicate 'process contains "LikeThese"' --debug --info --last 5m
```

### Excluding Extra Messages
If you notice spammy logs from subsystems like **AudioToolbox**, exclude them:
```bash
xcrun simctl spawn booted log stream \
  --predicate 'process contains "LikeThese" AND NOT eventMessage CONTAINS "AudioToolbox"' \
  --debug --info
```
Or for historical logs:
```bash
xcrun simctl spawn booted log show \
  --predicate 'process contains "LikeThese" AND NOT eventMessage CONTAINS "AudioToolbox"' \
  --debug --info --last 5m
```

### Excluding Multiple Frameworks at Once
If logs from external frameworks like AudioToolbox, VisionKit, CFNetwork, or CoreFoundation clutter your console, chain your excludes:
```bash
xcrun simctl spawn booted log stream \
  --predicate 'process contains "LikeThese" 
    AND NOT eventMessage CONTAINS "AudioToolbox" 
    AND NOT eventMessage CONTAINS "VisionKit" 
    AND NOT eventMessage CONTAINS "CFNetwork" 
    AND NOT eventMessage CONTAINS "CoreFoundation"' \
  --debug --info
```
This shows only **LikeThese** logs, excluding all unwanted frameworks.  




