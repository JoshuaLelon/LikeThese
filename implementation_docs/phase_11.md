## Phase 11: AI-Based "Least Similar" Video Replacement (Complete Flow)

### Overview
We'll now specify **exact models** from [Replicate Explore](http://replicate.com/explore) and **extract the first frame** of each candidate video using `ffmpeg` at runtime. The function calls:

1. **[andreasjansson/clip-features](https://replicate.com/andreasjansson/clip-features)** for embeddings.  
2. **[google/imagen-3-fast](https://replicate.com/google/imagen-3-fast)** for text-to-image (poster image).  

### Key Implementation Details

1. **Video Storage & Processing**
   - Videos are stored in Firebase Storage
   - Videos are TikTok-style format (1080×1920), under ~30 seconds
   - First frames will be generated at runtime, stored temporarily in `/tmp` (512MB limit)
   - Clean up temporary files immediately after embedding computation

2. **Scale & Performance**
   - MVP level implementation - handling 1 request every few seconds max
   - Board size is fixed at 4 videos (see USER_STORIES.md)
   - Process all available videos as candidates (excluding current board videos)
   - No caching implementation for now
   - Response time: A few seconds is acceptable for MVP

3. **Error Handling**
   - Single retry for Replicate API calls
   - Clear error messages to UI for:
     - Frame extraction failures
     - Embedding computation failures
     - Poster generation failures
   - Skip failed items when computing "least similar"
   - Use Firebase Functions default 60s timeout

4. **Infrastructure Requirements**
   - Firebase Functions: Default 256MB-1GB memory, 60s timeout
   - Custom Docker build needed for ffmpeg
   - Store Replicate API key in Firebase Functions config

### Checklist

1. **Update Embedding & Poster Image Steps**

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

   > **After** (partial snippet, specifying andreasjansson/clip-features):
   ```js
   async function getClipEmbedding(imageUrl, replicate) {
     const embedding = await replicate.run("andreasjansson/clip-features", {
       input: { image: imageUrl }
     });
     return embedding;
   }
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

   > **After** (using google/imagen-3-fast):
   ```js
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
   ```

2. **Extract the First Frame Dynamically**  

   - In the **`extractFrames`** (or renamed `extractSingleFrame`) helper, we only grab the beginning frame:
   ```js
   const { spawn } = require("child_process");
   const fs = require("fs");

   async function extractSingleFrame(videoUrl, localOutPath) {
     // Note: localOutPath should be in /tmp directory
     const tmpPath = `/tmp/${Date.now()}.jpg`;
     return new Promise((resolve, reject) => {
       // Using ffmpeg to grab the very first frame
       const ffmpegArgs = [
         "-i", videoUrl,
         "-frames:v", "1",
         "-f", "image2",
         tmpPath
       ];

       const ffmpeg = spawn("ffmpeg", ffmpegArgs);

       ffmpeg.on("close", (code) => {
         if (code === 0) resolve(tmpPath);
         else reject(new Error(`ffmpeg exited with code ${code}`));
       });
     });
   }
   ```

   - Update your main flow to:
     1. **Download** or reference the video by `videoUrl`.  
     2. Call `extractSingleFrame(videoUrl, "./temp.jpg")`.  
     3. Pass `"./temp.jpg"` to `getClipEmbedding`.  
     4. Delete `temp.jpg` after embedding is done (avoid storing).

3. **Function Configuration**
   ```bash
   # Set memory and timeout
   firebase functions:config:set memory=1GB timeout=60s

   # Set up Replicate API key
   firebase functions:config:set replicate.api_key="YOUR_REPLICATE_TOKEN"
   ```

4. **Implementation Notes**
   - Validate input URLs point to Firebase Storage
   - Log to LangSmith:
     - Inputs (board vs. candidate data)
     - Chosen result and distances
     - Total runtime
     - Embedding retrieval times
   - Response format:
     ```typescript
     interface Response {
       chosen: string;      // video ID
       score: number;       // similarity score
       posterImageUrl?: string; // optional poster URL
     }
     ```
   - Poster image should match vertical video format (1080×1920)

5. **Error Messages**
   Keep error messages simple but informative:
   ```typescript
   const ERROR_MESSAGES = {
     FRAME_EXTRACTION: "Failed to extract video frame",
     EMBEDDING: "Failed to compute video similarity",
     POSTER: "Failed to generate poster image",
     GENERAL: "Failed to process video request"
   };
   ```

6. **Confirm Flow Matches Diagram**
   - **ExtractFrames** → `extractSingleFrame` with `ffmpeg`.  
   - **ComputeEmbeddings** → `andreasjansson/clip-features`.  
   - **CompareEmbeddings** → `cosineDistance` loop.  
   - **PickLeastSimilar** → Highest sum of distances.  
   - **GeneratePosterImage** → `google/imagen-3-fast`.  
   - **LogRun** → `axios.post` to LangSmith.  
   - **ReturnVideoID** → `res.json(...)`.  
   - **UpdateGrid** → Handled in Swift app.

7. **Project & Dependencies**  
   - [ ] Go to your `functions` folder (created in earlier phases).  
   - [ ] Install Replicate (for embeddings and text-to-image) and a request library for LangSmith:
     ```bash
     npm install replicate axios
     ```
     *(Alternatively, you can use `fetch` if your Node version supports it.)*

8. **Environment Variables**  
   - [ ] Configure your **Replicate** API key:
     ```bash
     firebase functions:config:set replicate.api_key="YOUR_REPLICATE_TOKEN"
     ```
   - [ ] Configure any **LangSmith** endpoints/keys if needed (see their docs). For example:
     ```bash
     firebase functions:config:set langsmith.base_url="https://api.langsmith.com"
     firebase functions:config:set langsmith.api_key="YOUR_LANGSMITH_TOKEN"
     ```

9. **Implement "CandidateFlow" as a Single Cloud Function**  
   Create/update `functions/index.js` (or `functions/src/index.ts`), ensuring all steps match **FLOW_DIAGRAM.md**:

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
    - [ ] Deploy the function:
      ```bash
      firebase deploy --only functions
      ```
    - [ ] Send a test request from **Postman** or **Swift**:
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
    - [ ] Confirm the response includes:
      1. `chosenVideo`  
      2. `distanceScore`  
      3. `posterImageUrl` if `textPrompt` was given  

11. **Swift Integration**  
    - [ ] In your app's "Swipe Up" flow (see `FLOW_DIAGRAM.md`), call `POST` or use `Functions.httpsCallable("candidateFlow")`.
    - [ ] Once you receive `{ chosenVideo, posterImageUrl }`, replace the grid's video with `chosenVideo` and optionally display the "poster" in your UI.

12. **Validation of Diagram Steps**  
    - **ExtractFrames**: Provided as an optional function if you need dynamic frame generation.  
    - **ComputeEmbeddings**: Done with `getClipEmbedding()`.  
    - **CompareEmbeddings**: The loop with `cosineDistance()`.  
    - **PickLeastSimilar**: The highest total distance.  
    - **GeneratePosterImage**: The `generatePosterImage()` function with text prompt.  
    - **LogRun**: The `axios.post()` call to LangSmith.  
    - **ReturnVideoID**: The `res.json({ chosenVideo, ... })` in the function response.  
    - **UpdateGrid**: Handled in Swift once the function response is received.

13. **Troubleshooting**
    - If you see an error like **"ModuleNotFoundError: ffmpeg or replicate**:  
      - Double-check your `npm install replicate axios`.  
    - If the function times out:  
      - Increase the function's [timeout settings](https://firebase.google.com/docs/functions/manage-functions#set_timeout_and_memory_allocation).  
    - If LangSmith logging fails:  
      - Confirm you used the right `base_url` and `api_key`.

14. **Wrap-Up**  
    With these steps, **FLOW_DIAGRAM.md** is fully realized in Node-based Firebase Functions. You'll have:
    1. **Frame extraction** (optional).  
    2. **Embedding** with Replicate.  
    3. **Distance-based** "least similar" selection.  
    4. **Poster image** generation.  
    5. **LangSmith** logging.  
    6. **Clean return** to iOS.

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