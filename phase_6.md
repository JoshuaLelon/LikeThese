# Phase 6: Firebase Storage and Connectivity Findings

## Data Structure Discrepancy
We discovered a mismatch between our ER diagram and actual Firestore implementation:

### ER Diagram Structure
```
VIDEO {
    string videoId
    string videoFilePath     // Firebase Storage path
    string thumbnailFilePath // Firebase Storage path for thumbnail
}
```

### Actual Firestore Document Structure
```typescript
interface VideoDocument {
    id: string
    url: string             // Direct URL to video in Firebase Storage
    thumbnailUrl: string    // Direct URL to thumbnail in Firebase Storage
    timestamp: Timestamp
}
```

## Firebase Storage URLs
- Current Implementation: Using direct storage URLs
  ```
  https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/videos/playing_with_soccer_ball.mp4
  https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/thumbnails/playing_with_soccer_ball.jpg
  ```
- Storage Rules: Currently in test mode (not recommended for production)
  ```rules
  match /{allPaths=**} {
      allow read, write: if true;  // Test mode - DO NOT USE IN PRODUCTION
  }
  ```

## Connectivity Handling
We've implemented robust connectivity handling:

1. Network Monitoring
```swift
private let networkMonitor = NWPathMonitor()
private var isNetworkAvailable = true
```

2. Offline Persistence
```swift
let settings = FirestoreSettings()
settings.isPersistenceEnabled = true
settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
```

3. Network State Changes
- Monitors connectivity changes
- Automatically re-enables Firestore network when connection is restored
- Implements retry logic for failed operations

## Error Handling
We've identified and handle several types of errors:

```swift
enum FirestoreError: Error {
    case invalidVideoURL(String)
    case emptyVideoCollection
    case invalidVideoData
    case networkError(Error)
    case maxRetriesReached
}
```

## Retry Mechanism
Implemented a robust retry system:
- Maximum 3 retry attempts
- 1-second delay between retries
- Exponential backoff for network errors
- Specific handling for Firebase and POSIX errors

## URL Handling Strategy
The system now handles both storage paths and direct URLs:

1. Video URL Resolution:
```swift
// Tries in this order:
1. Direct URL from "url" field
2. Storage path from "videoFilePath" field
```

2. Thumbnail URL Resolution:
```swift
// Tries in this order:
1. Direct URL from "thumbnailUrl" field
2. Storage path from "thumbnailFilePath" field
```

## Video Playback Issues
We've identified issues with video playback after successful data fetching:

### Error Flow
```
1. ✅ Network connection established
2. ✅ Firestore documents fetched successfully
3. ✅ Video URLs validated and processed
4. ✅ Cache service initialized
5. ❌ Video playback fails with "Asset is not playable"
```

### Sample Video Processing Flow
```swift
// Successful document fetch
📄 Document data: [
    "url": "https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/videos/playing_with_soccer_ball.mp4",
    "thumbnailUrl": "https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/thumbnails/playing_with_soccer_ball.jpg",
    "id": "playing_with_soccer_ball",
    "timestamp": <FIRTimestamp>
]

// Successful validation
✅ Using direct video URL
✅ Using direct thumbnail URL
✅ Successfully validated video data

// Cache initialization
📼 VideoCacheService initialized at /Users/.../VideoCache

// Playback attempt
🔄 Preloading video from URL
❌ Error: Asset is not playable
```

### Potential Causes
1. CORS (Cross-Origin Resource Sharing) restrictions on Firebase Storage
2. Video format incompatibility
3. Invalid or expired Firebase Storage URLs
4. Network connectivity issues during video download
5. Insufficient permissions at the Storage bucket level

## Known Issues
1. Network connectivity errors may require multiple retries
2. Thumbnail failures are non-blocking but not recovered
3. Direct URLs vs Storage paths inconsistency needs resolution
4. Video playback fails despite successful data fetching
5. Firebase Storage URLs might require additional authentication or headers
6. Video caching mechanism might not be properly handling download failures

## Recommendations

### Short Term
1. Standardize the data structure:
   - Either update ER diagram to match current implementation
   - Or migrate Firestore data to use storage paths

2. Update Firebase Storage rules for production:
```rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /videos/{videoId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```

3. Verify Firebase Storage CORS settings:
   ```bash
   gsutil cors get gs://likethese-fc23d.firebasestorage.app
   ```

4. Add video format validation before playback attempt

5. Implement proper error handling for video loading failures

### Long Term
1. Consider implementing a CDN for better video delivery
2. Add video format validation
3. Implement video transcoding for different qualities
4. Add proper error recovery for thumbnail failures
5. Implement proper video caching strategy

6. Consider implementing a video transcoding pipeline
7. Add support for adaptive bitrate streaming (HLS)
8. Implement proper video format validation before upload

## Next Steps
1. Verify Firebase Storage CORS configuration
2. Add logging for video format and size before playback attempt
3. Implement proper error handling in VideoPlayerView
4. Test with different video formats to identify compatibility issues
5. Consider implementing a video health check before playback

## Logging
Implemented comprehensive logging using `os.Logger`:
- Network state changes
- Document processing
- URL resolution
- Error conditions
- Operation retries 