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
