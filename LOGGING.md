# LikeThese Logging Documentation

## Overview
This document outlines the logging system used throughout the LikeThese app. The logging system is designed to provide comprehensive debugging information, track user interactions, and monitor system performance.

## Logging System Architecture

### Logger Setup
Each component uses Apple's unified logging system with a dedicated subsystem and category:
```swift
import os
private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "ComponentName")
```

### Subsystems and Categories
- **VideoPlayback**: Main video playback interface
- **VideoPlayer**: Individual video player components
- **VideoManager**: Video state and resource management
- **FirestoreService**: Firebase interactions
- **VideoCacheService**: Video caching operations
- **AuthService**: Authentication operations

## Log Categories and Emojis

### User Interface (📱)
- View lifecycle events
- UI state changes
- Layout updates
- User interface interactions

### Loading and Progress (⌛️)
- Content loading states
- Progress updates
- Initialization events
- Resource loading

### User Actions (👤)
- Gesture interactions
- Button taps
- Navigation actions
- User preferences

### System Operations (🔄)
- Background tasks
- Resource management
- Cache operations
- State synchronization

### Network Status (🌐)
- Connectivity changes
- API requests
- Download status
- Network quality

### Playback Status (🎮)
- Video player states
- Playback controls
- Media loading
- Player configuration

### Performance Metrics (📊)
- Buffer progress
- Queue management
- Resource usage
- Timing measurements

### Resource Management (🧹)
- Cleanup operations
- Memory management
- Resource deallocation
- Cache maintenance

### Success Events (✅)
- Operation completion
- Resource loading
- State transitions
- Validation success

### Errors and Warnings (❌/⚠️)
- Operation failures
- Resource issues
- State conflicts
- System warnings

### Gesture Tracking (🖐️)
- Touch interactions
- Swipe events
- Gesture states
- Input handling

### Automated Actions (🤖)
- System-initiated events
- Scheduled tasks
- Auto-advance operations
- Background processes

## Log Format

### Standard Format
```
{timestamp} {app}[{process}:{thread}] {emoji} {CATEGORY}: {description}
```

### Example Log Analysis
```
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




