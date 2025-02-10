# Firebase Functions for LikeThese

This directory contains the Firebase Functions implementation for the LikeThese app's AI-based video replacement feature.

## Setup

1. Install dependencies:
```bash
npm install
```

2. Configure Firebase:
```bash
# Set memory and timeout
firebase functions:config:set memory=1GB timeout=60s

# Set up Replicate API key
firebase functions:config:set replicate.api_key="YOUR_REPLICATE_TOKEN"

# Set up LangSmith (optional)
firebase functions:config:set langsmith.base_url="https://api.langsmith.com"
firebase functions:config:set langsmith.api_key="YOUR_LANGSMITH_TOKEN"
```

## Development

1. Start the emulator:
```bash
npm run serve
```

2. Deploy to Firebase:
```bash
npm run deploy
```

## Function: findLeastSimilarVideo

This function implements the AI-based "least similar" video replacement logic:

1. Uses pre-generated thumbnails from Firebase Storage
2. Computes CLIP embeddings using [andreasjansson/clip-features](https://replicate.com/andreasjansson/clip-features)
3. Finds the most dissimilar video using cosine distance
4. Optionally generates a poster image using [google/imagen-3-fast](https://replicate.com/google/imagen-3-fast)
5. Logs the run to LangSmith (if configured)

### Input Format
```typescript
interface Input {
  boardVideos: Array<{ id: string, url: string, thumbnailUrl: string }>;
  candidateVideos: Array<{ id: string, url: string, thumbnailUrl: string }>;
  textPrompt?: string;
}
```

### Output Format
```typescript
interface Output {
  chosenVideo: string;      // video ID
  score: number;           // similarity score
  posterImageUrl?: string; // optional poster URL
}
```

## Infrastructure

- Uses Node.js 18 runtime
- 1GB memory allocation
- 60-second timeout
- Uses pre-generated thumbnails from seeding process

## Error Handling

The function implements:
- Single retry for Replicate API calls
- Clear error messages for:
  - Thumbnail access failures
  - Embedding computation failures
  - Poster generation failures
- Skip failed items when computing "least similar"
- Uses Firebase Functions default 60s timeout 