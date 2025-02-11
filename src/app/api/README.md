## Firebase Functions

### extractVideoFrame
- **Purpose**: Extracts the first frame from a video URL using ffmpeg
- **Input**: Video URL
- **Output**: Frame URL in Firebase Storage
- **Error Handling**: Falls back to existing thumbnail if frame extraction fails

### findLeastSimilarVideo
- **Purpose**: Finds videos most dissimilar to current board
- **Input**: Board ID, excluded video IDs
- **Output**: Sorted array of candidate videos based on cosine distance
- **Caching**: Uses cached embeddings when available
- **Error Handling**: Returns random video if embedding calculation fails 