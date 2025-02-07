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

## Grid Layout Implementation

### InspirationsGridView
The grid layout has been optimized for a 2x2 video display with the following features:

- Responsive sizing based on screen dimensions
- Maintains 9:16 video aspect ratio
- 36pt spacing between videos for clear visual separation and touch targets
- 1pt padding around grid edges
- Dynamic height calculation based on available width
- Smooth animations during video transitions

### Key Implementation Details
- Uses LazyVGrid for efficient video rendering
- GeometryReader for responsive calculations
- Preserves video aspect ratios without stretching
- Optimized for different screen sizes
- Wide spacing (36pt) to improve visual hierarchy and touch interaction

### Grid Layout Flow
1. Screen width determines video dimensions
2. Videos maintain 9:16 aspect ratio
3. 36pt gaps provide clear visual separation and touch targets
4. 1pt edge padding prevents overflow
5. Smooth animations during video removal/replacement

This implementation ensures:
- Consistent video appearance across devices
- No stretching or distortion of videos
- Clear visual separation between videos
- Comfortable touch targets for gestures
- Efficient use of screen space
- Smooth transitions during interactions
- Enhanced visual feedback during swipes:
  - Progressive opacity changes
  - Subtle scale reduction
  - 3D rotation effects
  - Double-tap haptic feedback
  - Spring-based animations