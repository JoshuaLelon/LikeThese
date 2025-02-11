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
154|
155| ### 9. Final Notes & Future Considerations
156| 1. [ ] **Performance**: On-demand frame extraction can be expensive. Consider an offline or one-time migration approach.  
157| 2. [ ] **Caching**: If your library is large, store embeddings in Firestore after extraction so you don't recalc them every time.  
158| 3. [ ] **Error Handling**: If ffmpeg fails, revert to old thumbnail or skip the video.  
159| 4. [ ] **Possible Enhancements**: Add a multi-swipe feature that toggles between your newly sorted queue and a random selection for wildcard variety.  
160|
161| ---
162| **End of Phase 12**  