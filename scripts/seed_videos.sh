#!/bin/bash

# Configuration
VIDEO_DIR="sample_data/videos"
THUMBNAIL_DIR="sample_data/thumbnails"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Set up Python virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}Setting up Python virtual environment...${NC}"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
else
    source venv/bin/activate
fi

# Check if Firebase CLI is installed and logged in
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}Firebase CLI is not installed. Please install it first:${NC}"
    echo "npm install -g firebase-tools"
    exit 1
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    echo -e "${RED}gsutil (Google Cloud SDK) is not installed. Please install it first:${NC}"
    echo "On macOS with Homebrew:"
    echo "brew install --cask google-cloud-sdk"
    echo -e "\nThen authenticate with:"
    echo "gcloud auth login"
    echo "gcloud config set project likethese-fc23d"
    exit 1
fi

# Check if we're logged into Firebase
if ! firebase projects:list &> /dev/null; then
    echo -e "${RED}Not logged into Firebase. Please run:${NC}"
    echo "firebase login"
    exit 1
fi

# Create directories if they don't exist
mkdir -p "$VIDEO_DIR"
mkdir -p "$THUMBNAIL_DIR"

# Check if we have videos
video_count=$(ls -1 "$VIDEO_DIR"/*.mp4 2>/dev/null | wc -l)
if [ "$video_count" -eq 0 ]; then
    echo -e "${RED}No videos found in $VIDEO_DIR${NC}"
    echo "Please add .mp4 videos (1080x1920 resolution) to this directory"
    exit 1
fi

# Check if we have thumbnails
thumbnail_count=$(ls -1 "$THUMBNAIL_DIR"/*.jpg 2>/dev/null | wc -l)
if [ "$thumbnail_count" -eq 0 ]; then
    echo -e "${YELLOW}No thumbnails found in $THUMBNAIL_DIR${NC}"
    echo "Generating thumbnails from videos..."
    
    # Check if ffmpeg is installed
    if ! command -v ffmpeg &> /dev/null; then
        echo -e "${RED}ffmpeg is not installed. Please install it first:${NC}"
        echo "brew install ffmpeg"
        exit 1
    fi
    
    # Generate thumbnails for each video
    for video in "$VIDEO_DIR"/*.mp4; do
        basename=$(basename "$video" .mp4)
        echo "Generating thumbnail for $basename..."
        ffmpeg -i "$video" -vframes 1 "$THUMBNAIL_DIR/${basename}.jpg" -y
    done
fi

echo -e "${GREEN}Starting upload to Firebase...${NC}"

# Upload videos and create Firestore documents
for video in "$VIDEO_DIR"/*.mp4; do
    basename=$(basename "$video" .mp4)
    thumbnail="$THUMBNAIL_DIR/${basename}.jpg"
    
    echo "Processing $basename..."
    
    # Check if video already exists in Firebase
    if gsutil ls "gs://likethese-fc23d.firebasestorage.app/videos/${basename}.mp4" &> /dev/null; then
        echo "Video $basename already exists, skipping..."
        continue
    fi
    
    # Upload video
    echo "Uploading video $basename..."
    if ! gsutil cp "$video" "gs://likethese-fc23d.firebasestorage.app/videos/${basename}.mp4"; then
        echo -e "${RED}Failed to upload video $basename${NC}"
        continue
    fi
    
    # Upload thumbnail
    echo "Uploading thumbnail for $basename..."
    if ! gsutil cp "$thumbnail" "gs://likethese-fc23d.firebasestorage.app/thumbnails/${basename}.jpg"; then
        echo -e "${RED}Failed to upload thumbnail for $basename${NC}"
        continue
    fi
    
    # Get download URLs
    video_url=$(gsutil signurl -d 7d "gs://likethese-fc23d.firebasestorage.app/videos/${basename}.mp4" | awk 'NR==2{print $5}')
    thumbnail_url=$(gsutil signurl -d 7d "gs://likethese-fc23d.firebasestorage.app/thumbnails/${basename}.jpg" | awk 'NR==2{print $5}')
    
    # Create Firestore document
    echo "Creating Firestore document for $basename..."
    firebase firestore:set --project=likethese-fc23d "videos/$basename" "{
        videoFilePath: 'gs://likethese-fc23d.firebasestorage.app/videos/${basename}.mp4',
        thumbnailFilePath: 'gs://likethese-fc23d.firebasestorage.app/thumbnails/${basename}.jpg',
        createdAt: $(date +%s)
    }"
    
    echo -e "${GREEN}Successfully processed $basename${NC}"
done

echo -e "${GREEN}Upload process complete!${NC}"

# Verify uploads
echo -e "\n${YELLOW}Verifying uploads...${NC}"

# Check Storage
echo -e "\nChecking Firebase Storage:"
echo "Videos:"
gsutil ls gs://likethese-fc23d.firebasestorage.app/videos/
echo -e "\nThumbnails:"
gsutil ls gs://likethese-fc23d.firebasestorage.app/thumbnails/

echo -e "\n${GREEN}Verification complete!${NC}" 