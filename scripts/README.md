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

This script generates AI-powered thumbnails for videos using Replicate's imagen-3-fast model.

#### Technical Details
- Uses imagen-3-fast to generate images directly at 1080x1920 (TikTok format)
- Generates one thumbnail per video to avoid excessive API usage
- Maintains 9:16 aspect ratio throughout the process

#### Setup
1. Install required packages:
```bash
/usr/local/bin/pip3.11 install -r scripts/requirements.txt
```

2. Ensure you have a Replicate API token in your `.env` file:
```env
REPLICATE_API_TOKEN=your_token_here
```

#### Usage
Run the script using:
```bash
/usr/local/bin/python3.11 scripts/generate_thumbnails.py
```

The script will:
- Look for .mp4 files in `sample_data/videos/`
- Generate thumbnails using Replicate's imagen-3-fast model
- Automatically resize to TikTok format (1080x1920)
- Save thumbnails in `sample_data/thumbnails/<video_name>/`
- Use video filenames as inspiration for thumbnail generation

#### Requirements
- Replicate API key
- Python 3.11
- Required packages (installed via requirements.txt):
  - replicate>=0.25.1 (for Replicate API)
  - python-dotenv>=1.0.0 (for .env file support)
  - Pillow>=10.0.0 (for image resizing)

#### Notes
- Imagen-3-fast generates images at the exact resolution we need (1080x1920)
- The script uses high-quality LANCZOS resampling for any necessary resizing
- Rate limiting is implemented to respect Replicate's API limits 