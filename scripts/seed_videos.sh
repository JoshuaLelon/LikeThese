#!/bin/bash

# Configuration
VIDEO_DIR="sample_data/videos"
THUMBNAIL_DIR="sample_data/thumbnails"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section header
print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Set up Python virtual environment if it doesn't exist
print_section "Setting up environment"
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}Setting up Python virtual environment...${NC}"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    pip install --upgrade pip
    pip install pyopenssl cryptography
else
    source venv/bin/activate
    pip install pyopenssl cryptography
fi

# Check if Firebase CLI is installed and logged in
print_section "Checking prerequisites"
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

# Get list of existing files in Firebase Storage
print_section "Checking Firebase Storage"
echo -e "${YELLOW}Checking existing files in Firebase Storage...${NC}"
existing_videos=$(gsutil ls gs://likethese-fc23d.firebasestorage.app/videos/*.mp4 2>/dev/null)
existing_thumbnails=$(gsutil ls gs://likethese-fc23d.firebasestorage.app/thumbnails/*.jpg 2>/dev/null)
video_count=$(echo "$existing_videos" | grep -c "^" || true)
thumbnail_count=$(echo "$existing_thumbnails" | grep -c "^" || true)

if [ "$video_count" -gt 0 ] && [ "$thumbnail_count" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $video_count videos and $thumbnail_count thumbnails in Firebase Storage${NC}"
    echo -e "${YELLOW}Skipping video and thumbnail upload...${NC}"
    echo -e "${YELLOW}Proceeding to verify Firestore documents...${NC}"
else
    print_section "Processing local files"
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
            echo -e "${YELLOW}Generating thumbnail for $basename...${NC}"
            ffmpeg -i "$video" -vframes 1 "$THUMBNAIL_DIR/${basename}.jpg" -y
            echo -e "${GREEN}✓ Generated thumbnail for $basename${NC}"
        done
    fi

    print_section "Uploading to Firebase Storage"
    echo -e "${GREEN}Starting upload to Firebase...${NC}"

    # Upload videos and thumbnails
    for video in "$VIDEO_DIR"/*.mp4; do
        basename=$(basename "$video" .mp4)
        thumbnail="$THUMBNAIL_DIR/${basename}.jpg"
        
        echo -e "\n${YELLOW}Processing $basename...${NC}"
        
        # Upload video
        echo "Uploading video $basename..."
        if ! gsutil cp "$video" "gs://likethese-fc23d.firebasestorage.app/videos/${basename}.mp4"; then
            echo -e "${RED}Failed to upload video $basename${NC}"
            continue
        fi
        echo -e "${GREEN}✓ Uploaded video $basename${NC}"
        
        # Upload thumbnail
        echo "Uploading thumbnail for $basename..."
        if ! gsutil cp "$thumbnail" "gs://likethese-fc23d.firebasestorage.app/thumbnails/${basename}.jpg"; then
            echo -e "${RED}Failed to upload thumbnail for $basename${NC}"
            continue
        fi
        echo -e "${GREEN}✓ Uploaded thumbnail for $basename${NC}"
        
        echo -e "${GREEN}✓ Successfully processed $basename${NC}"
    done
fi

# Verify and create Firestore documents if needed
print_section "Managing Firestore Documents"
echo -e "${GREEN}Checking and creating Firestore documents...${NC}"
echo "$existing_videos" | while read -r video; do
    [ -z "$video" ] && continue
    basename=$(basename "$video" .mp4)
    echo -e "\n${YELLOW}Processing $basename...${NC}"
    
    # Check if document exists
    if node scripts/update_firestore.js check "$basename"; then
        echo -e "${GREEN}✓ Document already exists for $basename${NC}"
    else
        echo -e "${YELLOW}Document missing for $basename, creating...${NC}"
        
        # Create Firestore document using Node.js script
        if node scripts/update_firestore.js create "$basename"; then
            echo -e "${GREEN}✓ Successfully created document for $basename${NC}"
        else
            echo -e "${RED}✗ Failed to create document for $basename${NC}"
            exit 1
        fi
    fi
done

# Print summary
print_section "Summary"
echo -e "Videos in Storage: ${GREEN}$video_count${NC}"
echo -e "Thumbnails in Storage: ${GREEN}$thumbnail_count${NC}"
echo -e "\n${YELLOW}Video files:${NC}"
echo "$existing_videos"
echo -e "\n${YELLOW}Thumbnail files:${NC}"
echo "$existing_thumbnails"

# Print all Firestore documents
print_section "Current Firestore Documents"
node scripts/update_firestore.js list

echo -e "\n${GREEN}✓ Verification complete!${NC}" 