# LikeThese

## Development

### Building & Running
To build and run the app during development:

1. Using SweetPad UI:
   - Click the "Clean" option in the schema context menu
   - Click the "Build & Run" button (▶️)

2. Using Terminal:
   ```bash
   sweetpad clean && sweetpad build && sweetpad launch
   ```

### Prerequisites
- Xcode 15.0 or later
- iOS 17.0 or later
- SweetPad extension for VS Code/Cursor
- Firebase project with Storage enabled

### Hot Reload with InjectionIII
For a faster development loop, we use [InjectionIII](https://github.com/johnno1962/InjectionIII) to inject Swift code changes directly into the running simulator:

1. Install InjectionIII from the Mac App Store or GitHub.  
2. Launch it and select your running **LikeThese** simulator process under "Select App."  
3. Make sure you're using a **Debug** build.  
4. Save any Swift file to see the updated code injected automatically.

## Scripts

This project includes several utility scripts for data management and content generation:

1. [Database Seeding](scripts/README.md#seed_videossh) - Upload test videos to Firebase
2. [AI Thumbnail Generation](scripts/README.md#generate_thumbnailspy) - Generate AI-powered thumbnails using DALL-E 3

See [Scripts Documentation](scripts/README.md) for detailed setup and usage instructions.

## Seeding Test Data

### Overview
We use a simple bash script that leverages the Firebase CLI to seed our database with test videos. The script:
1. Automatically generates thumbnails from videos using ffmpeg
2. Uploads videos and thumbnails to Firebase Storage
3. Creates Firestore documents linking to the uploaded files

### One-Time Setup
1. Install Node.js and npm (if not already installed):
   ```bash
   brew install node
   ```

2. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```

3. Install ffmpeg (for thumbnail generation):
   ```bash
   brew install ffmpeg
   ```

4. Log into Firebase:
   ```bash
   firebase login
   ```

5. Make the script executable:
   ```bash
   chmod +x scripts/seed_videos.sh
   ```

### Adding Test Videos
1. Create the videos directory:
   ```bash
   mkdir -p sample_data/videos
   ```

2. Add your test videos:
   - Place 12 .mp4 files in `sample_data/videos/`
   - Videos must be 1080x1920 resolution (TikTok format)
   - Videos should be reasonably sized (a few MB each)

### Running the Seeder
1. From project root:
   ```bash
   ./scripts/seed_videos.sh
   ```

2. The script will:
   - Create thumbnails automatically in `sample_data/thumbnails/`
   - Upload videos to Firebase Storage under `videos/`
   - Upload thumbnails to Firebase Storage under `thumbnails/`
   - Create a Firestore document for each video with:
     - Video URL
     - Thumbnail URL
     - Creation timestamp

3. Progress and errors will be shown in the terminal

### File Structure
```
LikeThese/
├── scripts
│   └── seed_videos.sh      # The main seeding script
├── sample_data
│   ├── videos             # Put your .mp4 files here
│   │   ├── video1.mp4
│   │   └── ...
│   └── thumbnails         # Generated automatically
│       ├── thumb1.jpg
│       └── ...
└── (remaining project files)
```

### Important Notes
- Videos must be TikTok resolution (1080x1920)
- The seeding process requires Firebase CLI and login
- Large videos may take time to upload
- Make sure you have enough Firebase Storage quota
- Script is idempotent (safe to run multiple times)
- Already uploaded videos will be skipped

## Debugging & Logs
If you need to view simulator logs for **LikeThese** in real time, run:
```bash
xcrun simctl spawn booted log stream --predicate 'process contains "LikeThese"' --debug --info
```
This outputs logs continuously while the app is running in the simulator.

If you need to view logs from the *past* 5 minutes, use:
```bash
xcrun simctl spawn booted log show --predicate 'process contains "LikeThese"' --debug --info --last 5m
```

### Excluding Extra Messages (e.g., AudioToolbox, VisionKit, CFNetwork)
If you see other frameworks spamming your logs, you can chain multiple exclude conditions:
```bash
xcrun simctl spawn booted log stream \
  --predicate 'process contains "LikeThese" 
    AND NOT eventMessage CONTAINS "AudioToolbox" 
    AND NOT eventMessage CONTAINS "VisionKit" 
    AND NOT eventMessage CONTAINS "CFNetwork" 
    AND NOT eventMessage CONTAINS "CoreFoundation"' \
  --debug --info
```


---

## Known Mermaid Diagram Errors and Fixes

Below is a summary of the parse errors we ran into during this conversation, along with their root causes and how we fixed them.

### 1) Error: "Parse error on line…" involving parentheses or quotes in node labels

> **Example Snippet (Trigger)**  
> ```
> CompareEmbeddings[Compare vs. Board Embeddings
> (Replicate CLIP Model)]
> ```
> **Error**:  
> ```
> Diagram syntax error
> Expecting 'SQE' ... got 'PS'
> ```
>  
> **Root Cause**  
> Mermaid sometimes chokes on unescaped parentheses or quotes directly in node labels.  
>  
> **Fix**  
> We removed or escaped parentheses and used simpler labels, e.g.:  
> ```
> CompareEmbeddings[Compare vs board with cosine distance]
> ```
>  
> **What Led to the Fix**  
> After repeated errors, we realized removing parentheses/quotes or escaping them (`\( \)`) resolves the parse issue.

---

### 2) Error: "Parse error on line…" involving curly quotes or special characters

> **Example Snippet (Trigger)**  
> ```
> CandidateFlow((Compute "Least Similar"
> via Replicate
> +Optional LangSmith))
> ```
> **Error**:  
> ```
> Diagram syntax error
> Expecting ... got 'STR'
> ```
>  
> **Root Cause**  
> Curly quotes ("" or "") or multi-line strings in a Mermaid label cause parse issues.  
>  
> **Fix**  
> Replace curly quotes with straight quotes or remove quotes entirely. Also avoid abrupt line breaks.  
>  
> **What Led to the Fix**  
> We systematically removed curly quotes and restricted multiline text to `<br/>` or shorter single-line labels.

---

### 3) Error: "Parse error on line…" when using code fences and markdown simultaneously

> **Example Snippet (Trigger)**  
> ```
> ```mermaid
> graph LR
> ...
> ```
> ```
> (Nested code blocks can break rendering in some contexts.)
>  
> **Root Cause**  
> Nested triple-backtick blocks can confuse the parser if not well-formed in Markdown.  
>  
> **Fix**  
> We ensured we had properly opened and closed code fences once, and used a single ` ```mermaid ` or ` ``` ` block.  
>  
> **What Led to the Fix**  
> Observing that removing nested triple backticks eliminated parse breaks.

---

### 4) Error: "Parse error" whenever special punctuation or partial lines remained

> **Example Snippet (Trigger)**  
> ```
> text # "Compute 'least similar' ...
> Autoplay Next Video (Random)"
> ```
> **Root Cause**  
> If punctuation like `(`, `'`, or `"` is placed in a node label incorrectly, Mermaid's parser fails.  
>  
> **Fix**  
> We replaced or removed parentheses and quotes, or used `\(` and `\)` as escapes where needed.  
>  
> **What Led to the Fix**  
> Ongoing trial and error showed that removing or escaping these characters in node labels allowed successful parsing.

---

## Summary

1. **List of errors**: All centered on Mermaid parse errors.  
2. **Root causes**: Unescaped parentheses, curly quotes, special punctuation, or multiline labels.  
3. **Fix approach**: Remove or escape problematic characters, simplify labels, avoid nested code blocks or curly quotes.  
4. **Explanation**: By limiting node labels to plain text without parentheses/curly quotes, or by properly escaping them, we resolved the parsing issues.

That covers all the errors we encountered, why they happened, and how we fixed them.

## Features

### Phase 12: Extended AI Flow & First-Frame Extraction
- Dynamic first frame extraction using ffmpeg
- Sorted video queue based on board average embedding
- Sequential playback in fullscreen mode
- Hybrid approach for thumbnails/frames (uses existing thumbnails when available)
- Improved error handling and fallback mechanisms

## Project Structure
```
LikeThese/
├── implementation_docs/
│   ├── phase_11.md         # Core AI similarity implementation
│   └── phase_12.md         # Extended AI flow & frame extraction
├── scripts/
│   ├── seed_videos.sh      # The main seeding script
│   └── README.md           # Scripts documentation
├── sample_data/
│   ├── videos/             # Test video files
│   └── thumbnails/         # Generated thumbnails & frames
└── src/
    └── app/
        ├── api/            # Firebase Functions & API docs
        └── components/     # React components & docs
```