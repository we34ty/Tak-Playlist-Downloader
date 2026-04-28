#!/bin/bash
echo "Building Tak Playlist Downloader for Linux..."
echo ""

# Check if virtual environment exists, create if not
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies in virtual environment
echo "Installing dependencies..."
pip install schedule pystray pillow pyinstaller

# Clean previous build
rm -rf build dist *.spec

# Build executable with all hidden imports
echo "Building executable..."
pyinstaller --onefile --windowed \
    --name "Tak-Playlist-Downloader" \
    --hidden-import=schedule \
    --hidden-import=pystray \
    --hidden-import=PIL \
    --hidden-import=PIL.Image \
    --hidden-import=PIL.ImageDraw \
    --hidden-import=tkinter \
    --hidden-import=threading \
    --hidden-import=subprocess \
    --hidden-import=json \
    --hidden-import=datetime \
    --hidden-import=pathlib \
    --hidden-import=uuid \
    --hidden-import=queue \
    --hidden-import=atexit \
    --collect-all schedule \
    --collect-all pystray \
    Tak-Playlist-Downloader.py

# Copy the .sh scripts to the dist folder (they need to be alongside the executable)
echo "Copying script files to dist folder..."
cp Download-Playlist.sh dist/
cp Retry-Failed.sh dist/
cp Move-Recovered.sh dist/

echo ""
echo "Build complete! Executable is in the 'dist' folder."
echo "Run with: ./dist/Tak-Playlist-Downloader"
