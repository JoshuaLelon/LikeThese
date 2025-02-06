# Views

## Video Playback Implementation

### VideoPlaybackView and VideoPlayerView
The video playback system has been optimized for smooth full-screen transitions using a fixed current video and animated incoming video approach:

- Current video remains pinned in place
- Only the incoming video animates during transitions
- Single offset animation for clean transitions
- Proper aspect ratio handling with `.aspectRatio(contentMode: .fill)`

### Key Implementation Details
- VideoPlayerView is simplified to avoid nested geometry readers
- VideoPlaybackView uses a single GeometryReader to size both videos
- Transitions are handled by animating only the incoming video's offset
- Safe area handling is consistent across all video views

### Transition Flow
1. Current video stays fixed at its position
2. Incoming video starts off-screen (above or below)
3. Incoming video animates to center position
4. Opacity crossfade happens during transition
5. Clean state reset after transition completes

This implementation ensures:
- No flickering during transitions
- No offset issues with video positioning
- Smooth gesture-based navigation
- Proper video scaling and aspect ratio handling 