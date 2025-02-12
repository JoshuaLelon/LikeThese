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
    pip install google-cloud-aiplatform
else
    source venv/bin/activate
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
video_count=$(echo "$existing_videos" | grep -c "^" || true)

if [ "$video_count" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $video_count videos in Firebase Storage${NC}"
    echo -e "${YELLOW}Processing existing videos for Gemini embeddings...${NC}"
    
    # Process all videos for Gemini embeddings using Node.js script
    echo "$existing_videos" | while read -r video; do
        [ -z "$video" ] && continue
        basename=$(basename "$video" .mp4)
        echo -e "\n${YELLOW}Processing Gemini embedding for $basename...${NC}"
        node functions/gemini_processor.js process "$basename"
    done
    
    echo -e "${YELLOW}Proceeding to verify Firestore documents...${NC}"
else
    echo -e "${RED}No videos found in Firebase Storage${NC}"
    exit 1
fi

# Verify and update Firestore documents if needed
print_section "Managing Firestore Documents"
echo -e "${GREEN}Checking and updating Firestore documents with Gemini data...${NC}"
echo "$existing_videos" | while read -r video; do
    [ -z "$video" ] && continue
    basename=$(basename "$video" .mp4)
    echo -e "\n${YELLOW}Processing $basename...${NC}"
    
    # Check if document has Gemini data
    if node functions/gemini_processor.js check "$basename"; then
        echo -e "${GREEN}✓ Gemini data already exists for $basename${NC}"
    else
        echo -e "${YELLOW}Gemini data missing for $basename, processing...${NC}"
        
        # Process with Gemini using Node.js script
        if node functions/gemini_processor.js process "$basename"; then
            echo -e "${GREEN}✓ Successfully added Gemini data for $basename${NC}"
        else
            echo -e "${RED}✗ Failed to process Gemini data for $basename${NC}"
            # Continue with next video instead of exiting
            continue
        fi
    fi
done

# Print summary
print_section "Summary"
echo -e "Videos processed: ${GREEN}$video_count${NC}"

# Print all Firestore documents with Gemini data
print_section "Current Gemini Processing Status"
node functions/gemini_processor.js list

echo -e "\n${GREEN}✓ Gemini processing complete!${NC}" 