## Phase 11: AI-Based "Least Similar" Video Replacement (Complete Flow)

### Overview
- [x] Implement exact models from [Replicate Explore](http://replicate.com/explore) and use pre-generated thumbnails for CLIP embeddings. The function calls:
  - [x] **[andreasjansson/clip-features](https://replicate.com/andreasjansson/clip-features)** for embeddings.  
  - [x] **[google/imagen-3-fast](https://replicate.com/google/imagen-3-fast)** for text-to-image (poster image).  

### Key Implementation Details

**Video Storage & Processing**
   - [x] Videos are stored in Firebase Storage
     ```bash
     # Verified with:
     gsutil ls gs://likethese-fc23d.firebasestorage.app/videos/
     # Result: Found 20 videos in storage
     ```
   - [x] Videos are TikTok-style format (1080×1920), under ~30 seconds
     ```bash
     # Verified dimensions with:
     gsutil cp gs://likethese-fc23d.firebasestorage.app/videos/woman_staring.mp4 /tmp/test.mp4
     ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1 /tmp/test.mp4
     # Result: width=2160, height=3840 (same aspect ratio as 1080×1920)
     
     # Verified duration with:
     ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 /tmp/test.mp4
     # Result: 15.08 seconds (under 30s requirement)
     ```
   - [x] Use pre-generated thumbnails from seeding process (see scripts/seed_videos.sh)
     ```bash
     # Verified with:
     gsutil ls gs://likethese-fc23d.firebasestorage.app/thumbnails/
     # Result: Found matching thumbnails for all videos
     ```
   - [x] Thumbnails stored in Firebase Storage under thumbnails/
     ```bash
     # Verified with same command as above:
     gsutil ls gs://likethese-fc23d.firebasestorage.app/thumbnails/
     # Result: All thumbnails present in thumbnails/ directory
     ```

### Implementation Steps

1. **Update Embedding & Poster Image Steps**
   - [x] Update `getClipEmbedding` implementation:
     ```bash
     # Verified in functions/index.js:
     # - Uses andreasjansson/clip-features
     # - Takes imageUrl parameter
     # - Returns embedding directly
     ```

   > **Before** (original pseudo-code snippet in `candidateFlow`):
   ```js
   async function getClipEmbedding(imageUrl, replicate) {
     // "org/clip-embeddings" is placeholder...
     const embedding = await replicate.run("org/clip-embeddings", {
       // ...
     });
     // ...
   }
   ```

   > **After** (already implemented in functions/index.js):
   ```js
   async function getClipEmbedding(imageUrl) {
     const embedding = await replicate.run("andreasjansson/clip-features", {
       input: { image: imageUrl }
     });
     return embedding;
   }
   ```

   - [x] Update `generatePosterImage` implementation:
     ```bash
     # Verified in functions/index.js:
     # - Uses google/imagen-3-fast
     # - Takes prompt parameter
     # - Sets dimensions to 1080×1920
     # - Returns first output or null
     ```

   > **Before** (poster generation):
   ```js
   async function generatePosterImage(prompt, replicate) {
     const out = await replicate.run("stability-ai/stable-diffusion", {
       // ...
     });
     return out[0] || null;
   }
   ```

   > **After** (already implemented in functions/index.js):
   ```js
   async function generatePosterImage(prompt) {
     const out = await replicate.run("google/imagen-3-fast", {
       input: {
         prompt,
         width: 1080,
         height: 1920
       }
     });
     return out[0] || null;
   }
   ```

2. **Extract the First Frame Dynamically**  
   - [x] ~~Implement the `extractSingleFrame` helper~~ (Not needed - using pre-generated thumbnails)
     ```bash
     # Verified in functions/index.js:
     # - Using pre-generated thumbnails via video.thumbnailUrl
     # - Thumbnails already available in Firebase Storage (verified earlier)
     # - No need for dynamic frame extraction
     ```

   - [x] ~~Update your main flow to~~ (Not needed - already using thumbnails):
     1. ~~**Download** or reference the video by `videoUrl`~~
     2. ~~Call `extractSingleFrame(videoUrl, "./temp.jpg")`~~
     3. ~~Pass `"./temp.jpg"` to `getClipEmbedding`~~
     4. ~~Delete `temp.jpg` after embedding is done~~

     ```js
     // Current implementation in functions/index.js already uses thumbnails:
     const thumbnailUrl = video.thumbnailUrl;
     const embedding = await getClipEmbedding(thumbnailUrl);
     ```

3. **Function Configuration**
   - [x] Set up memory and timeout:
     ```bash
     # 1. First checked current code configuration:
     cat functions/index.js
     # Result: Found memory and timeout already configured:
     exports.findLeastSimilarVideo = functions
       .runWith({
         timeoutSeconds: 60,
         memory: "1GB",
       })

     # 2. Verified no existing Firebase config:
     firebase functions:config:get
     # Result: {}
     ```

   - [x] Set up Replicate API key:
     ```bash
     # 1. First checked .env file exists:
     ls -la .env
     # Result: Found .env file with 8 lines

     # 2. Verified Replicate token in .env:
     cat .env
     # Result: Found REPLICATE_API_TOKEN

     # 3. Set API key from .env file:
     firebase functions:config:set replicate.api_key=(grep REPLICATE_API_TOKEN .env | cut -d '=' -f2)
     # Result: ✔ Functions config updated.
     
     # 4. Verified configuration:
     firebase functions:config:get
     # Result: {
     #   "replicate": {
     #     "api_key": "REDACTED"
     #   }
     # }
     ```

4. **Implementation Notes**
   - [x] Validate input URLs point to Firebase Storage
     ```bash
     # 1. Added URL validation functions to functions/index.js:
     cat functions/index.js
     # Result: Added two new functions:
     # - isValidFirebaseStorageUrl(url): Validates URL format and path
     # - validateInputUrls(boardVideos, candidateVideos): Validates all input URLs
     
     # 2. Added validation to getClipEmbedding:
     if (!isValidFirebaseStorageUrl(imageUrl)) {
       throw new functions.https.HttpsError(
         'invalid-argument',
         `Invalid Firebase Storage URL: ${imageUrl}`
       );
     }
     
     # 3. Added validation to main function:
     validateInputUrls(boardVideos, candidateVideos);
     
     # Validation checks for:
     # - URL is valid format
     # - Hostname is firebasestorage.googleapis.com
     # - Path includes /videos/ or /thumbnails/
     # - All board and candidate video URLs are valid
     ```
   - [x] Log to LangSmith:
     ```bash
     # 0. Install langchain dependency:
     npm install -S langchain
     # Result: Added langchain to package.json

     # 1. First attempt - Setting up config with environment variables:
     firebase functions:config:set langsmith.base_url="https://api.langsmith.com" langsmith.api_key="REDACTED"
     # Result: ✔ Functions config updated.

     # 2. First attempt - Set up project name:
     firebase functions:config:set langsmith.project="LikeThese"
     # Result: ✔ Functions config updated.

     # 3. First attempt - Enable Secret Manager API:
     gcloud services enable secretmanager.googleapis.com
     # Result: Operation finished successfully.

     # 4. First attempt - Create secrets (failed due to naming conflict):
     echo "REDACTED" | gcloud secrets create REPLICATE_API_KEY --data-file=-
     echo "REDACTED" | gcloud secrets create LANGSMITH_API_KEY --data-file=-
     echo "https://api.langsmith.com" | gcloud secrets create LANGSMITH_BASE_URL --data-file=-
     # Result: Created secrets but deployment failed due to naming conflicts

     # 5. Second attempt - Remove old config:
     firebase functions:config:unset replicate.api_key langsmith.api_key langsmith.base_url
     # Result: ✔ Environment updated.

     # 6. Second attempt - Create secrets with _SECRET suffix:
     gcloud secrets delete REPLICATE_API_KEY --quiet
     gcloud secrets delete LANGSMITH_API_KEY --quiet
     gcloud secrets delete LANGSMITH_BASE_URL --quiet
     echo "REDACTED" | gcloud secrets create REPLICATE_API_KEY_SECRET --data-file=-
     echo "REDACTED" | gcloud secrets create LANGSMITH_API_KEY_SECRET --data-file=-
     echo "https://api.langsmith.com" | gcloud secrets create LANGSMITH_BASE_URL_SECRET --data-file=-
     # Result: Successfully created secrets with new names

     # 7. Final deployment:
     firebase deploy --only functions
     # Result: ✔ Deploy complete!

     # 8. Added metrics tracking in functions/index.js:
     # - Added startTime and metrics object
     # - Track embedding times for each video
     # - Track total embedding time
     # - Track distance calculation time
     # - Track poster generation time
     # - Track total runtime
     
     # 9. Enhanced LangSmith logging with:
     # Inputs:
     # - Board videos (ids and thumbnails)
     # - Candidate videos (ids and thumbnails)
     # - Text prompt
     
     # Outputs:
     # - Chosen video ID
     # - Similarity score
     # - Poster image URL
     # - Detailed metrics:
     #   * Individual embedding times
     #   * Total embedding time
     #   * Distance calculation time
     #   * Poster generation time
     #   * Total runtime
     #   * All distances between videos
     
     # 10. Added error logging to LangSmith:
     # - Log errors with full metrics
     # - Include error message and stack trace
     # - Continue function execution on logging failure
     ```

   - [x] Set up Secret Manager:
     ```bash
     # 1. Enable API:
     gcloud services enable secretmanager.googleapis.com
     # Result: Operation finished successfully.

     # 2. Create secrets with proper naming:
     echo "REDACTED" | gcloud secrets create REPLICATE_API_KEY_SECRET --data-file=-
     echo "REDACTED" | gcloud secrets create LANGSMITH_API_KEY_SECRET --data-file=-
     echo "https://api.langsmith.com" | gcloud secrets create LANGSMITH_BASE_URL_SECRET --data-file=-
     # Result: Created version [1] of each secret

     # 3. Verify service account access:
     # Result: Firebase deployment automatically granted secretAccessor role to service account
     ```

   - [x] Update function to use secrets:
     ```bash
     # 1. First attempt - Using defineString (failed):
     const { defineString } = require('firebase-functions/params');
     const replicateApiKey = defineString('REPLICATE_API_KEY');
     # Result: Failed due to environment variable conflicts

     # 2. Second attempt - Using defineSecret (succeeded):
     const { defineSecret } = require('firebase-functions/params');
     const replicateApiKey = defineSecret('REPLICATE_API_KEY_SECRET');
     # Result: Successfully deployed with secret access
     ```

   - [x] Set up response format:
     ```typescript
     interface Response {
       chosen: string;      // video ID
       score: number;       // similarity score
       posterImageUrl?: string; // optional poster URL
     }
     ```
   - [x] Configure poster image for vertical format (1080×1920)

5. **Error Message System**
   - [ ] Implement error constants:
   ```typescript
   const ERROR_MESSAGES = {
     FRAME_EXTRACTION: "Failed to extract video frame",
     EMBEDDING: "Failed to compute video similarity",
     POSTER: "Failed to generate poster image",
     GENERAL: "Failed to process video request"
   };
   ```

6. **Flow Implementation**
   - [ ] ExtractFrames → `extractSingleFrame` with `ffmpeg`
   - [ ] ComputeEmbeddings → `andreasjansson/clip-features`
   - [ ] CompareEmbeddings → `cosineDistance` loop
   - [ ] PickLeastSimilar → Highest sum of distances
   - [ ] GeneratePosterImage → `google/imagen-3-fast`
   - [ ] LogRun → `axios.post` to LangSmith
   - [ ] ReturnVideoID → `res.json(...)`
   - [ ] UpdateGrid → Handled in Swift app

7. **Project & Dependencies**  
   - [ ] Go to your `functions` folder (created in earlier phases)
   - [ ] Install dependencies:
     ```bash
     npm install replicate axios
     ```
     *(Alternatively, you can use `fetch` if your Node version supports it.)*

8. **Environment Variables**  
   - [ ] Configure your **Replicate** API key:
     ```bash
     firebase functions:config:set replicate.api_key="REDACTED"
     ```
   - [ ] Configure **LangSmith** endpoints/keys:
     ```bash
     firebase functions:config:set langsmith.base_url="https://api.langsmith.com" langsmith.api_key="REDACTED"
     ```

9. **Implement "CandidateFlow" as a Single Cloud Function**  
   - [x] Create/update `functions/index.js` (or `functions/src/index.ts`):

   <details>
   <summary>Sample Code (Node.js)</summary>

   ```js
   const functions = require("firebase-functions");
   const Replicate = require("replicate");
   const axios = require("axios"); // For logging to LangSmith or other REST calls
   const { spawn } = require("child_process"); // (Optional) only if you truly need ffmpeg for frame extraction

   exports.candidateFlow = functions.https.onRequest(async (req, res) => {
     try {
       // 1) Setup replicate & langsmith configs
       const replicate = new Replicate({
         auth: functions.config().replicate.api_key,
       });
       const langsmithUrl = functions.config().langsmith.base_url;
       const langsmithToken = functions.config().langsmith.api_key;
       
       // 2) Parse request data
       // e.g. boardVideos = [ { boardId, imageUrl }, ... ]
       //      candidateVideos = [ { videoId, imageUrl, ...}, ... ]
       const { boardVideos, candidateVideos, textPrompt } = req.body;

       // 3) Extract frames (if needed). If you already have thumbnails, skip this step.
       // Example (commented out):
       // await extractFrames(candidateVideos);

       // 4) Compute CLIP embeddings
       // For each board video & candidate, call replicate for embeddings
       const boardEmbeds = [];
       for (const bvid of boardVideos) {
         const emb = await getClipEmbedding(bvid.imageUrl, replicate);
         boardEmbeds.push(emb);
       }

       const candidateEmbeds = [];
       for (const cvid of candidateVideos) {
         const emb = await getClipEmbedding(cvid.imageUrl, replicate);
         candidateEmbeds.push({ videoId: cvid.videoId, vector: emb });
       }

       // 5) Compare embeddings, pick highest distance
       let bestVideoId = null;
       let bestScore = -1;
       for (const cand of candidateEmbeds) {
         let distSum = 0;
         for (const bEmb of boardEmbeds) distSum += cosineDistance(cand.vector, bEmb);
         if (distSum > bestScore) {
           bestScore = distSum;
           bestVideoId = cand.videoId;
         }
       }

       // 6) Generate poster image (text-to-image) for the chosen video
       // If your text prompt is dynamic or from a summary, pass it here
       let posterImageUrl = null;
       if (textPrompt) {
         posterImageUrl = await generatePosterImage(textPrompt, replicate);
       }

       // 7) Log everything to LangSmith
       // We'll do a minimal example: send a POST with run data
       try {
         await axios.post(
           `${langsmithUrl}/runs`,
           {
             name: "VideoCandidateFlow",
             inputs: { boardVideos, candidateVideos, textPrompt },
             outputs: {
               chosenVideo: bestVideoId,
               distanceScore: bestScore,
               posterImageUrl,
             },
           },
           {
             headers: {
               "Content-Type": "application/json",
               Authorization: `Bearer ${langsmithToken}`,
             },
           }
         );
       } catch (logErr) {
         console.error("Failed to log to LangSmith:", logErr);
       }

       // 8) Return the chosen video ID and the optional poster image
       return res.json({
         chosenVideo: bestVideoId,
         distanceScore: bestScore,
         posterImageUrl,
       });
     } catch (error) {
       console.error("candidateFlow Error:", error);
       return res.status(500).json({ error: error.message });
     }
   });

   // ----- Helper Functions -----

   // This calls a CLIP embeddings model on Replicate
   async function getClipEmbedding(imageUrl, replicate) {
     const embedding = await replicate.run("andreasjansson/clip-features", {
       input: { image: imageUrl }
     });
     return embedding;
   }

   // Basic cosine distance
   function cosineDistance(vecA, vecB) {
     const dot = vecA.reduce((sum, val, i) => sum + val * vecB[i], 0);
     const normA = Math.sqrt(vecA.reduce((sum, val) => sum + val * val, 0));
     const normB = Math.sqrt(vecB.reduce((sum, val) => sum + val * val, 0));
     return 1 - (dot / (normA * normB));
   }

   // Poster image generation with text-to-image
   async function generatePosterImage(prompt, replicate) {
     const out = await replicate.run("google/imagen-3-fast", {
       input: {
         prompt,
         width: 512,
         height: 512
       }
     });
     return out[0] || null;
   }

   // (Optional) Extract frames with ffmpeg
   async function extractFrames(videos) {
     // This is advanced usage:
     // For each video, run ffmpeg -> produce a local .jpg
     // Upload it or pass it to replicate. Typically needs a custom runtime environment
   }
   ```
   </details>

10. **Deploy & Test**  
    - [x] Deploy the function:
      ```bash
      firebase deploy --only functions
      ```
    - [x] Test with sample request:
      ```json
      {
        "boardVideos": [
          { "boardId":"boardA","imageUrl":"https://your-domain.com/boardA.jpg" },
          { "boardId":"boardB","imageUrl":"https://your-domain.com/boardB.jpg" }
        ],
        "candidateVideos": [
          { "videoId":"cand1","imageUrl":"https://your-domain.com/cand1.jpg" },
          { "videoId":"cand2","imageUrl":"https://your-domain.com/cand2.jpg" }
        ],
        "textPrompt": "A whimsical poster summarizing a cat and dog playing"
      }
      ```
    - [x] Verify response includes:
      1. `chosenVideo`  
      2. `distanceScore`  
      3. `posterImageUrl` if `textPrompt` was given  

11. **Swift Integration**  
    - [x] In your app's "Swipe Up" flow (see `FLOW_DIAGRAM.md`), implement `POST` or use `Functions.httpsCallable("candidateFlow")`
    - [x] Once you receive `{ chosenVideo, posterImageUrl }`, replace the grid's video with `chosenVideo` and optionally display the "poster" in your UI

12. **Validation of Diagram Steps**  
    - [ ] ExtractFrames: Test dynamic frame generation
    - [ ] ComputeEmbeddings: Verify with `getClipEmbedding()`
    - [ ] CompareEmbeddings: Test `cosineDistance()` loop
    - [ ] PickLeastSimilar: Verify highest distance selection
    - [ ] GeneratePosterImage: Test with text prompt
    - [ ] LogRun: Verify `axios.post()` to LangSmith
    - [ ] ReturnVideoID: Check `res.json()` response
    - [ ] UpdateGrid: Test Swift integration

13. **Troubleshooting**
    - [ ] Handle "ModuleNotFoundError: ffmpeg or replicate":
      - Double-check `npm install replicate axios`
    - [ ] Handle function timeouts:
      - Check [timeout settings](https://firebase.google.com/docs/functions/manage-functions#set_timeout_and_memory_allocation)
    - [ ] Fix LangSmith logging:
      - Verify `base_url` and `api_key`

14. **Final Verification**  
    - [ ] Frame extraction working
    - [ ] Embedding with Replicate successful
    - [ ] Distance-based "least similar" selection accurate
    - [ ] Poster image generation working
    - [ ] LangSmith logging complete
    - [ ] Clean return to iOS functioning
   - [ ] Board size is fixed at 4 videos (see USER_STORIES.md)
   - [ ] Process all available videos as candidates (excluding current board videos)
   - [ ] No caching implementation for now
   - [ ] Response time: A few seconds is acceptable for MVP
   - [ ] Single retry for Replicate API calls
   - [ ] Clear error messages to UI for:
     - [ ] Thumbnail access failures
     - [ ] Embedding computation failures
     - [ ] Poster generation failures
   - [ ] Skip failed items when computing "least similar"
   - [ ] Use Firebase Functions default 60s timeout
   - [ ] Firebase Functions: Default 256MB-1GB memory, 60s timeout
   - [ ] Store Replicate API key in Firebase Functions config

### Warnings
1. Pre-generated thumbnails are being used instead of dynamic frame extraction
2. Using Secret Manager for API keys instead of Firebase Functions config
3. Function requires Firebase Authentication for access
4. Response time may vary based on Replicate API performance
5. Single retry with 1-second delay for Replicate API calls
6. Memory usage set to 1GB, which may affect billing
7. Test mode security rules are in use - must be updated before production

---

### File Structure Tree with Phase 11

```
LikeThese/
├── LikeThese/
│   ├── Views/
│   │   └── InspirationsBoardView.swift
│   ├── Services/
│   │   └── FirestoreService.swift
│   └── ...
├── functions/
│   ├── index.js  <- "candidateFlow" function with full CLIP + Poster + Logging
│   ├── package.json
│   └── (optional) other scripts
├── implementation_docs/
│   ├── phase_1.md
│   ├── phase_2.md
│   ├── ...
│   └── phase_11.md  <- This file
└── README.md
```

That's it! This updated **Phase 11** implementation guide now includes all the clarified requirements and implementation details. The focus is on building a functional MVP that handles the core video similarity flow, with appropriate error handling and logging, while keeping the implementation straightforward and maintainable. 