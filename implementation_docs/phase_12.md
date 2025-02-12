1| # Phase 12: Extended AI Flow & First-Frame Extraction
2|
3| ## Overview
4| In this phase, we're switching from static thumbnails to dynamically extracted first frames, plus implementing a user-driven "sorted queue" of videos:
5| - [x] **Frame Extraction**: Use ffmpeg to grab the first frame of each video instead of a pre-generated thumbnail, but only if no thumbnail exists.  
6| - [x] **Sorted Video Replacement**: After each single video replacement on the Inspirations board, create a list of all other videos and sort them in ascending order of cosine distance to the average of the current board's 4 videos.
7| - [PROGRESS] **Sequential Playback**: When the user is in fullscreen mode and swipes up, it steps through that sorted list in strict order.
8|
9| ## Detailed Checklist
10| Every sub-step is crucial for the final solution. If it's incomplete, the flow might fail. 
11|
12| ---
13|
14| ### 1. Dynamic First-Frame Extraction
15| 1. [x] **Install `ffmpeg`** on either your CI/CD or hosting environment (Google Cloud Functions, etc.). Make sure the function has permissions to execute it if sandboxing is in effect.
16| 2. [x] **Create/Update `extractSingleFrame(videoUrl, outputPath)`**:
17|    - Use `child_process.spawn` or `child_process.exec` to run:
18|      ```bash
19|      ffmpeg -i <videoUrl> -frames:v 1 -q:v 2 <outputPath>
20|      ```
21|    - Confirm that the resulting image is valid (e.g., ~JPEG/PNG).  
22| 3. [x] **Store the Extracted Frame**:
23|    - After extraction, upload it to Firebase Storage under `/frames/<videoId>.jpg`.  
24|    - Optionally use `admin.storage().bucket().upload(...)` with `public: true`, or store privately and generate signed URLs.  
25| 4. [x] **Link the Extracted Frame**:
26|    - In Firestore (videos collection), store a new field `frameUrl` for each video. When you finish extraction, set `frameUrl: "gs://..."`.
27| 5. [x] **Remove Old Thumbnail Logic**:
28|    - In `getClipEmbedding(...)`, replace references to `thumbnailUrl` with the new `frameUrl`.  
29|    - Validate the `frameUrl` again with `isValidFirebaseStorageUrl`. 
30| 6. [x] **Update Seeding Script**:
31|    - Modify the seeding script to use the same frame extraction logic
32|    - Check if a thumbnail exists first
33|    - If no thumbnail exists, extract first frame using ffmpeg
34|    - Store the frame URL in both `thumbnailUrl` and `frameUrl` fields for backward compatibility
35| 7. [x] **Update Frame Extraction Logic**:
36|    - When extracting frames, first check if a thumbnail exists in the document
37|    - If thumbnail exists, use that as the frame (copy URL to `frameUrl`)
38|    - If no thumbnail exists, use ffmpeg to extract first frame
39|    - Store result in both `thumbnailUrl` and `frameUrl` fields
40|
41| ---
42|
43| ### 2. Board Embedding Average & Sorted Queue
44| 1. [x] **Compute Board Average**:
45|    - After a single replacement, recalculate the **average embedding** of the 4 videos on the board.  
46|    - You can do it similar to:
47|      ```js
48|      function computeAverageEmbedding(embeddingsArray) {
49|        const length = embeddingsArray[0].length;
50|        const sum = Array(length).fill(0);
51|        for (const emb of embeddingsArray) {
52|          for (let i = 0; i < length; i++) {
53|            sum[i] += emb[i];
54|          }
55|        }
56|        return sum.map(val => val / embeddingsArray.length);
57|      }
58|      ```
59|    - Store that average in a local variable or pass it directly to the sorting routine. 
60| 2. [x] **Filter Out Board Videos**:
61|    - From the entire video library, exclude the 4 that are currently on the board (or any the user explicitly removed).  
62| 3. [x] **Get & Sort All Remaining Embeddings**:
63|    - Pull embeddings (via `getEmbeddingsWithCache()`) for all remaining videos.  
64|    - Compute cosine distance between each embedding and your newly computed **average**.  
65|    - Sort in ascending order (closest to average first, furthest last).
66| 4. [x] **Store Sorted List**:
67|    - Return it from the Firebase function or store it in a collection (like `videoQueues/{boardId}`) for later.  
68|    - When the user swipes up in fullscreen, the app will fetch from the top of that list. 
69|
70| ---
71|
72| ### 3. Fullscreen "Swipe Up" Flow
73| 1. [x] **Use the Sorted List**:
74|    - On the client, once the user transitions to fullscreen, keep a local pointer (e.g., `nextVideoIndex = 0`) in the sorted array.  
75| 2. [x] **Swipe Up -> Show Next**:
76|    - When the user swipes up, load `sortedList[nextVideoIndex]`, increment `nextVideoIndex`.  
77|    - If you run off the end of the array, either fetch more videos or revert to random.  
78| 3. [x] **Backward Compatibility**:
79|    - If the server didn't generate or return a sorted list (error?), fallback to the existing "least similar" logic.  
80| 4. [x] **Edge Cases**:
81|    - If the board changes while in fullscreen, you might need to refresh that sorted list or handle the discrepancy gracefully.  
82|
83| ---
84|
85| ### 4. Server-Side Implementation (Firebase Functions)
86| 1. [x] **Add `extractSingleFrame()`**:
87|    - Place this near `getClipEmbedding()` or in a separate utility file.  
88|    - Add logs and error handling with `functions.logger` or `console.log`. 
89| 2. [x] **Modify or Create a Function**:
90|    - Possibly name it `extractAndEmbedVideo(...)`, separate from `findLeastSimilarVideo`.  
91|    - Steps:
92|      1. Grab the video from Firebase Storage (or a recognized URL).  
93|      2. Extract the first frame with ffmpeg.  
94|      3. Upload that frame to `/frames/<videoId>.jpg`.  
95|      4. Compute the CLIP embedding from that frame.  
96|      5. Save `frameUrl` and `clipEmbedding` back to Firestore.  
97|    - Decide if you want to run this once for each video upfront or on-demand when the user requests a video.  
98| 3. [x] **Board Average & Sorting**:
99|    - Extend `exports.findLeastSimilarVideo` or create a new function.  
100|    - Pull embeddings for the 4 board videos, compute the average.  
101|    - Pull embeddings for all *other* videos, compute distance to the average, then sort.  
102|    - Return the sorted list to the client (structured as an array of `{ videoId, distance }`). 
103| 4. [x] **Update Database**:
104|    - Store the sorted queue or store it in ephemeral memory. Decide which approach suits best.  
105| 5. [x] **Logging & Error Handling**:
106|    - Use the same approach as `phase_11` to log each operation to LangSmith.  
107|    - If frame extraction fails, fallback to the current thumbnail approach or mark the video as "unavailable."  
108|
109| ---
110|
111| ### 5. Client-Side (Swift / iOS) Adjustments
112| 1. [x] **Board Replacement**:
113|    - On single swipe up in the board, call `findLeastSimilarVideo` (or an updated function) to:
114|      - Replace that singled-out video
115|      - Return the sorted queue for subsequent swipes in fullscreen
116| 2. [x] **Fullscreen Playback**:
117|    - Keep a local array `sortedCandidates`.  
118|    - If not empty, swiping up in fullscreen fetches the next from `sortedCandidates`.  
119|    - If empty or you hit the end, maybe fetch a fresh queue or revert to random.  
120|
121| ---
122|
123| ### 6. Testing & Verification
124| 1. [x] **Frame Extraction**: Validate that the "first frame" images you extract look correct in Firebase Storage.  
125| 2. [x] **Embedding Calculation**: Confirm that newly computed embeddings are in Firestore as expected.  
126| 3. [x] **Board Average**: Check logs to ensure the average embedding is computed each time you do a replacement.  
127| 4. [x] **Sorted Queue**: Dump out the sorted array from your function logs to confirm the order.  
128| 5. [x] **Swipe Up in Fullscreen**: Confirm that each subsequent swipe up picks the next item from that queue.  
129| 6. [x] **Error Cases**: Force an ffmpeg error or an invalid video URL to ensure fallback logic.  
130|
131| ---
132|
133| ### 7. Deployment
134| 1. [x] **Ensure `ffmpeg`** is installed in your environment or included in your build.  
135| 2. [x] **Deploy updates** to Firebase Functions:
136|    ```bash
137|    firebase deploy --only functions
138|    ```
139| 3. [x] **Refresh** your iOS code and confirm the new endpoints.  
140| 4. [x] **Test thoroughly** in staging before releasing to production.  
141|
142| ---
143|
144| ### 8. Documentation Updates
145| 1. [x] **Update All Relevant READMEs**:
146|    - [x] **Root `README.md`**: Add an entry describing Phase 12, referencing dynamic frame extraction and the new sorted queue logic.  
147|    - [x] **`implementation_docs/phase_11.md`**: Add a note that we now have "Phase 12" for advanced features.  
148|    - [x] **`implementation_docs/phase_12.md`** (this file): Ensure it's included in your top-level project tree docs.  
149| 2. [x] **Flow Diagrams**:
150|    - [x] Expand `FLOW_DIAGRAM.md` or add a new "phase 12" section describing the new BFS or sequential queue flow.  
151|    - [x] Clarify anywhere references to "thumbnailUrl" now become "frameUrl."  
152|
153| ---
159.1| 
159.2| **Implementation Plan: Textual Approach**  
159.8|    - [PROGRESS] Replace CLIP embeddings with text-based approach:
159.9|      - [x] Remove all CLIP-related code from `index.js`
159.10|      - [x] Update Firestore schema to replace `clipEmbedding` with `textEmbedding`
159.12|      - [x] Update all functions to use text embeddings for similarity matching

159.13|    - [PROGRESS] Modify seeding script (`seed_videos.sh`):
159.14|      - [x] Add Salesforce BLIP integration for image-to-text
159.15|      - [x] Add OpenAI text embedding generation
159.16|      - [x] Add timing/logging using LangSmith format
159.17|      - [x] Store both caption and embedding in Firestore

159.18|    - [x] Technical specifications:
159.19|      - Model: `salesforce/blip:2e1dddc8621f72155f24cf2e0adbde548458d3cab9f00c0139eea840d0ac4746`
159.20|      - Configuration:
159.21|        ```javascript
159.22|        {
159.23|          input: {
159.24|            task: "image_captioning",
159.25|            image: "<frame_url>"
159.26|          }
159.27|        }
159.28|        ```
159.29|      - Expected output format:
159.30|        ```javascript
159.31|        {
159.32|          output: [{ text: "Caption: <generated_caption>" }]
159.33|        }
159.34|        ```

159.35|    - [ ] Error handling:
159.36|      - [ ] Log errors to LangSmith
159.37|      - [ ] Return error response without fallback
159.38|      - [ ] Update error messages in ERROR_MESSAGES object

159.39|    - [PROGRESS] Update existing update_firestore.js:
159.40|      - [x] Set up basic structure and imports
159.41|        - Added OpenAI to existing Firebase Admin and Replicate setup
159.42|        - Verified environment variables handling
159.43|      
159.44|      - [x] Add new core functions alongside existing ones:
159.45|        - [x] `getImageCaption(imageUrl)` - Uses BLIP for image captioning
159.46|        - [x] `getTextEmbedding(caption)` - Uses OpenAI for text embeddings
159.47|        - [x] `migrateDocument(basename)` - Updates single document with new approach
159.48|        - [x] `migrateAllDocuments()` - Processes all documents
159.49|        
159.50|      - [x] Update existing helper functions:
159.51|        - [x] Kept existing `checkDocument(basename)`
159.52|        - [x] Kept existing `getSignedUrl(filePath)`
159.53|        - [x] Added `hasTextEmbedding(basename)`
159.54|        - [x] Update `createDocument` to include text embeddings
159.55|        - [x] Update `updateDocument` to handle migration
159.56|        
159.57|      - [x] Modify command handling:
159.58|        - [x] Keep existing `check` command
159.59|        - [x] Update `create` to include text embeddings
159.60|        - [x] Update `update` to include migration
159.61|        - [x] Add `migrate` command
159.62|        - [x] Add `migrate-all` command
159.63|        - [x] Keep existing `list` command

#### Technical Specifications
- [x] BLIP model configuration:
  - Model: `salesforce/blip:2e1dddc8621f72155f24cf2e0adbde548458d3cab9f00c0139eea840d0ac4746`
  - Input/Output format as specified
- [x] OpenAI embedding model:
  - Using `text-embedding-ada-002`
  - Maintaining embedding format compatibility

#### Considerations
- [x] Decide on batch size for migrate-all to prevent timeout (set to 5 with configurable override)
- [x] Determine error handling strategy for failed migrations (implemented with try/catch and error logging)
- [x] Plan for handling rate limits from OpenAI and BLIP (implemented 2-second delay between batches)
- [x] Consider parallel processing for migration (implemented with Promise.all for batch processing)
- [x] Decide on retry strategy for failed API calls (implemented with error propagation and logging)

#### Warnings
1. Migration will modify existing documents while preserving CLIP embeddings
2. Process may be slow due to sequential API calls to both BLIP and OpenAI
3. Cost implications for API usage (both BLIP and OpenAI)
4. Need to ensure adequate error handling for failed API calls
5. Should maintain old CLIP embeddings during transition period
6. Migration process cannot be easily rolled back once started
7. Rate limits may affect migration speed (2-second delay between batches implemented)

159.40| ### Warnings:
159.41| 1. Breaking change - old CLIP embeddings will be incompatible
159.42| 2. Need to reprocess all existing videos with new embedding approach
159.43| 3. May need to update any UI components that depend on similarity scores
160|
161| ---
162|
163| ### 10. Function Response Format & Behavior
1. **Response Structure**
   ```typescript
   interface Response {
     chosen: string;                // ID of the chosen video
     sortedCandidates: Array<{     // All candidates sorted by similarity
       videoId: string;
       distance: number;
     }>;
     score: number;                // Similarity score
     posterImageUrl?: string;      // Optional poster URL
   }
   ```

2. **Embedding Format**
   - CLIP embeddings are 27-dimensional vectors
   - Values typically range from -0.05 to 0.05
   - Example embedding:
     ```javascript
     [
       -0.0437239371240139,
       -0.003614606335759163,
       0.009466157294809818,
       // ... (27 total values)
     ]
     ```

3. **URL Handling**
   - Function returns signed URLs for both videos and thumbnails
   - URLs include:
     - GoogleAccessId
     - Expiration timestamp
     - Cryptographic signature
   - Example URL format:
     ```
     https://storage.googleapis.com/[PROJECT_ID].firebasestorage.app/[PATH]?GoogleAccessId=[ID]&Expires=[TIMESTAMP]&Signature=[SIG]
     ```

4. **Success Indicators**
   - Logs show step-by-step progress:
     ```
     📤 Calling findLeastSimilarVideo with [N] board videos and [M] candidates
     📥 Received response from findLeastSimilarVideo
     📊 Received [K] sorted candidates
     ✅ Found chosen video: [VIDEO_ID]
     ```

5. **Error Handling**
   - Function includes retry logic (3 attempts)
   - Handles authentication errors gracefully
   - Returns clear error messages for:
     - Invalid responses
     - Missing videos
     - Network errors

6. **Performance Notes**
   - Response times typically under 2 seconds
   - Embedding computation is cached
   - URL signing adds minimal overhead


### 11. Gemini-Based Video Understanding
1. **Parallel Implementation Strategy**
   - [x] Keep existing seed script (`seed_videos.sh`) and its dependencies untouched
   - [x] Create parallel seed script (`seed_videos_gemini.sh`) based on new document schema
   - [x] Create parallel functions for Gemini-based processing
   - [x] Store both approaches in Firestore for comparison
   
   **Rationale for Dual Approach:**
   - Current approach (BLIP+OpenAI) provides fast, reliable baseline
   - Gemini offers potentially richer understanding but is experimental
   - Enables A/B testing and gradual transition
   - Provides fallback mechanism if Gemini processing fails
   - Allows comparison of embedding quality and user engagement

2. **New Document Schema**
   ```typescript
   interface VideoDocument {
     // ... existing fields ...
     geminiDescription?: string;    // Rich video description from Gemini
     geminiEmbedding?: number[];    // 768-dimensional vector from text-embedding-004
     geminiMetadata?: {
       processedAt: Timestamp;
       processingTime: number;
       confidence: number;
       error?: string;
     };
   }
   ```

3. **Implementation Steps**
   a. **Video Description Generation**
   - [x] Create `functions/gemini_processor.js`:
     ```javascript
     async function generateVideoDescription(videoUrl) {
       const client = genai.Client(api_key="GEMINI_API_KEY");
       return client.models.generate_content({
         model: 'gemini-2.0-flash-exp',
         contents: [
           {
             video: videoUrl,
             text: `Analyze this video in detail. Include:
               - Key actions and movements
               - Visual composition and style
               - Objects and their relationships
               - Temporal aspects (changes over time)
               - Distinctive features
               Format as a detailed, structured description.`
           }
         ],
         // Added parameters for consistency
         temperature: 0.3,
         maxOutputTokens: 1024,
         topK: 40,
         topP: 0.8
       });
     }
     ```

   b. **Text Embedding Generation**
   - [x] Add embedding function with caching:
     ```javascript
     async function generateGeminiEmbedding(text, videoId) {
       // Check cache first
       const doc = await db.collection('embeddings').doc(videoId).get();
       if (doc.exists && doc.data().timestamp > Date.now() - 7 * 24 * 60 * 60 * 1000) {
         return doc.data().embedding;
       }

       const client = genai.Client(api_key="GEMINI_API_KEY");
       const embedding = await client.models.embed_content({
         model: 'text-embedding-004',
         content: text
       });

       // Cache result
       await db.collection('embeddings').doc(videoId).set({
         embedding,
         timestamp: Date.now()
       });

       return embedding;
     }
     ```

   c. **Similarity Measurement with Fallback**
   - [x] Add to `functions/index.js`:
     ```javascript
     async function findSimilarVideosGemini(boardVideos, candidates) {
       try {
         // Try Gemini embeddings first
         const boardEmbeddings = await Promise.all(
           boardVideos.map(v => v.geminiEmbedding ?? v.textEmbedding)
         );
         const avgEmbedding = computeAverageEmbedding(boardEmbeddings);
         
         return candidates
           .map(video => ({
             videoId: video.id,
             distance: cosineDistance(video.geminiEmbedding ?? video.textEmbedding, avgEmbedding)
           }))
           .sort((a, b) => a.distance - b.distance);
       } catch (error) {
         console.error('Gemini similarity failed, falling back to text embeddings');
         // Fallback to existing approach
         return findSimilarVideos(boardVideos, candidates);
       }
     }
     ```

4. **Processing Strategy**
   a. **Upload-time Processing**
   ```javascript
   async function processVideoWithGemini(videoId) {
     const startTime = Date.now();
     try {
       // Get video URL
       const video = await db.collection('videos').doc(videoId).get();
       const videoUrl = video.data().url;

       // Generate description with retry logic
       const description = await retryWithBackoff(
         () => generateVideoDescription(videoUrl),
         3,
         1000
       );

       // Generate embedding
       const embedding = await generateGeminiEmbedding(description, videoId);

       // Update document
       await db.collection('videos').doc(videoId).update({
         geminiDescription: description,
         geminiEmbedding: embedding,
         geminiMetadata: {
           processedAt: admin.firestore.Timestamp.now(),
           processingTime: Date.now() - startTime,
           confidence: description.safetyRatings.overall
         }
       });
     } catch (error) {
       // Log error and fall back to existing approach
       console.error(`Gemini processing failed for ${videoId}:`, error);
       await db.collection('videos').doc(videoId).update({
         geminiMetadata: {
           processedAt: admin.firestore.Timestamp.now(),
           error: error.message
         }
       });
     }
   }
   ```

6. **Validation Metrics**
   - Description Quality:
     - Minimum length: 100 tokens

7. **Error Handling**
   - Retry Strategy:
     - Max attempts: 3
     - Backoff: 1s, 2s, 4s
     - Circuit breaker after 3 failures
   - Fallback:
     - Use existing BLIP+OpenAI on failure
     - Log errors to LangSmith
     - Alert on high error rates

### Warnings:
1. Gemini API is in early access and may have stability issues
2. Dual processing will increase API costs significantly
3. Storage requirements will double for embeddings
4. Migration process needs careful handling to prevent data loss
5. Performance impact of running parallel systems needs monitoring
6. Rate limits may affect processing speed
7. Backward compatibility must be maintained during transition
8. Error handling complexity increases with dual systems
9. API costs may be significant during testing phase
10. System complexity increases with parallel implementations

---
**End of Phase 12**  