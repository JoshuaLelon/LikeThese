import os
import json
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
import replicate

# Load environment variables from .env file
load_dotenv()

# Constants
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

def generate_prompt(title: str) -> str:
    """Generate a prompt for the thumbnail based on video title."""
    return f"A cinematic, high-quality thumbnail for a video titled '{title}'. Vertical format, TikTok style, 1080x1920."

def resize_image(image_content: bytes, target_size: tuple[int, int]) -> Image.Image:
    """Resize image to target size while maintaining aspect ratio."""
    image = Image.open(BytesIO(image_content))
    image = image.convert('RGB')
    
    # Calculate dimensions preserving aspect ratio
    aspect_ratio = target_size[0] / target_size[1]
    current_ratio = image.width / image.height
    
    if current_ratio > aspect_ratio:
        new_height = image.height
        new_width = int(aspect_ratio * new_height)
    else:
        new_width = image.width
        new_height = int(new_width / aspect_ratio)
    
    # Crop to center
    left = (image.width - new_width) // 2
    top = (image.height - new_height) // 2
    right = left + new_width
    bottom = top + new_height
    
    image = image.crop((left, top, right, bottom))
    image = image.resize(target_size, Image.Resampling.LANCZOS)
    
    return image

def generate_thumbnails(client: replicate.Client, video_paths: List[Path], thumbnails_dir: Path):
    """Generate thumbnails for each video using Replicate's imagen-3-fast."""
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
            
            # Use Replicate's imagen-3-fast model
            output = client.run(
                "google/imagen-3-fast",
                input={
                    "prompt": prompt,
                    "width": TARGET_WIDTH,
                    "height": TARGET_HEIGHT
                }
            )
            
            # Download the image
            image_url = output[0] if isinstance(output, list) else output
            image_response = requests.get(image_url)
            image_response.raise_for_status()
            
            # Save the image directly (no need to resize as we specified dimensions)
            with open(thumbnail_path, 'wb') as f:
                f.write(image_response.content)
            
            print(f"✓ Generated thumbnail for {video_title}")
            
            # Sleep to respect rate limits
            time.sleep(1)
            
        except Exception as e:
            print(f"\n❌ Failed to generate thumbnail for {video_title}: {str(e)}")

def main():
    try:
        parser = argparse.ArgumentParser(description='Generate video thumbnails using Replicate')
        parser.add_argument('--api-key', help='Replicate API key')
        args = parser.parse_args()
        
        # Get API key from args, environment, or .env file
        api_key = args.api_key or os.getenv('REPLICATE_API_TOKEN')
        if not api_key:
            raise ValueError("Replicate API key must be provided via --api-key argument or REPLICATE_API_TOKEN in .env file")
        
        # Initialize Replicate client
        client = replicate.Client(api_token=api_key)
        
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