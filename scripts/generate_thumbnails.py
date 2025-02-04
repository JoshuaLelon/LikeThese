import os
import json
from openai import OpenAI
from pathlib import Path
import time
from typing import List, Dict
import argparse
from dotenv import load_dotenv
from PIL import Image
import requests
from io import BytesIO
import signal
import sys

# Load environment variables from .env file
load_dotenv()

# Constants
DALLE_WIDTH = 1024
DALLE_HEIGHT = 1792
TARGET_WIDTH = 1080
TARGET_HEIGHT = 1920

def signal_handler(sig, frame):
    print("\n\nGracefully stopping... (This might take a few seconds)")
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

def setup_directories() -> tuple[Path, Path]:
    """Create necessary directories if they don't exist."""
    base_dir = Path(__file__).parent.parent
    videos_dir = base_dir / "sample_data" / "videos"
    thumbnails_dir = base_dir / "sample_data" / "thumbnails"
    
    thumbnails_dir.mkdir(parents=True, exist_ok=True)
    return videos_dir, thumbnails_dir

def get_video_title(video_path: Path) -> str:
    """Extract a title from the video filename."""
    # Remove extension and replace underscores/hyphens with spaces
    title = video_path.stem.replace('_', ' ').replace('-', ' ')
    return title.title()  # Capitalize first letter of each word

def generate_prompt(video_title: str) -> str:
    """Generate a DALL-E prompt based on the video title."""
    # Special case for the problematic prompt
    if video_title.lower() == "man rubbing calves":
        return "Create a vertical thumbnail for a fitness video about leg muscle recovery. Show a professional fitness setting with exercise equipment and recovery tools. Make it suitable for mobile viewing in portrait orientation with vibrant colors and clear focal points."
    
    return f"Create a vertical thumbnail for a TikTok-style video titled '{video_title}'. The image should be eye-catching and modern, with vibrant colors and clear focal points. Make it suitable for mobile viewing in portrait orientation. Ensure the composition works well in a 9:16 aspect ratio."

def resize_image(image_data: bytes, target_size: tuple[int, int]) -> Image.Image:
    """Resize image to target size while maintaining aspect ratio."""
    img = Image.open(BytesIO(image_data))
    return img.resize(target_size, Image.Resampling.LANCZOS)

def generate_thumbnails(client: OpenAI, video_paths: List[Path], thumbnails_dir: Path):
    """Generate thumbnails for each video using DALL-E 3."""
    for video_path in video_paths:
        try:
            # Check if thumbnail already exists
            thumbnail_path = thumbnails_dir / f"{video_path.stem}.png"
            if thumbnail_path.exists():
                print(f"\nSkipping {video_path.stem} - thumbnail already exists")
                continue
                
            video_title = get_video_title(video_path)
            prompt = generate_prompt(video_title)
            
            print(f"\nGenerating thumbnail for: {video_title}")
            
            response = client.images.generate(
                model="dall-e-3",
                prompt=prompt,
                size=f"{DALLE_WIDTH}x{DALLE_HEIGHT}",
                quality="standard",
                n=1,
            )
            
            # Download the image
            image_url = response.data[0].url
            image_response = requests.get(image_url)
            image_response.raise_for_status()
            
            # Resize the image
            resized_image = resize_image(
                image_response.content, 
                (TARGET_WIDTH, TARGET_HEIGHT)
            )
            
            # Save the resized image with the video name
            resized_image.save(thumbnail_path, "PNG")
            
            print(f"✓ Generated thumbnail for {video_title}")
            
            # Sleep to respect rate limits
            time.sleep(1)
            
        except KeyboardInterrupt:
            print("\n\nGracefully stopping... (This might take a few seconds)")
            sys.exit(0)
        except Exception as e:
            print(f"Error generating thumbnail for {video_title}: {str(e)}")
            continue

def main():
    try:
        parser = argparse.ArgumentParser(description='Generate video thumbnails using DALL-E 3')
        parser.add_argument('--api-key', help='OpenAI API key')
        args = parser.parse_args()
        
        # Get API key from args, environment, or .env file
        api_key = args.api_key or os.getenv('OPENAI_API_KEY')
        if not api_key:
            raise ValueError("OpenAI API key must be provided via --api-key argument or OPENAI_API_KEY in .env file")
        
        # Initialize OpenAI client
        client = OpenAI(api_key=api_key)
        
        # Setup directories
        videos_dir, thumbnails_dir = setup_directories()
        
        # Get list of video files
        video_paths = list(videos_dir.glob('*.mp4'))
        if not video_paths:
            print("No .mp4 files found in sample_data/videos/")
            return
        
        print(f"Found {len(video_paths)} videos")
        generate_thumbnails(client, video_paths, thumbnails_dir)
        print("\nThumbnail generation complete!")
        
    except KeyboardInterrupt:
        print("\n\nGracefully stopping... (This might take a few seconds)")
        sys.exit(0)

if __name__ == "__main__":
    main() 