# Scripts Documentation

## Python Environment Setup

This project uses Python 3.11 installed via Homebrew. Here's how to set up the environment:

1. Install Python 3.11 via Homebrew:
```bash
brew install python@3.11
```

2. The Python binary is installed at:
```bash
/usr/local/bin/python3.11
```

3. The pip binary is installed at:
```bash
/usr/local/bin/pip3.11
```

## Available Scripts

### generate_thumbnails.py

This script generates AI-powered thumbnails for videos using OpenAI's DALL-E 3 API.

#### Technical Details
- Uses DALL-E 3 to generate images at 1024x1792 (DALL-E's maximum supported vertical resolution)
- Automatically resizes images to 1080x1920 (TikTok format) using Pillow's high-quality LANCZOS resampling
- Generates one thumbnail per video to avoid excessive API usage
- Maintains 9:16 aspect ratio throughout the process

#### Setup
1. Install required packages:
```bash
/usr/local/bin/pip3.11 install -r scripts/requirements.txt
```

2. Ensure you have an OpenAI API key in your `.env` file:
```env
OPENAI_API_KEY=your_api_key_here
```

#### Usage
Run the script using:
```bash
/usr/local/bin/python3.11 scripts/generate_thumbnails.py
```

The script will:
- Look for .mp4 files in `sample_data/videos/`
- Generate thumbnails using DALL-E 3
- Automatically resize to TikTok format (1080x1920)
- Save thumbnails in `sample_data/thumbnails/<video_name>/`
- Use video filenames as inspiration for thumbnail generation

#### Requirements
- OpenAI API key
- Python 3.11
- Required packages (installed via requirements.txt):
  - openai>=1.12.0 (for DALL-E 3 API)
  - python-dotenv>=1.0.0 (for .env file support)
  - Pillow>=10.0.0 (for image resizing)

#### Notes
- DALL-E 3 has specific resolution constraints:
  - Supported sizes: 1024x1024, 1024x1792, 1792x1024
  - We use 1024x1792 and resize to match TikTok's 1080x1920
- The script uses high-quality LANCZOS resampling for the best possible image quality
- Rate limiting is implemented to respect OpenAI's API limits 