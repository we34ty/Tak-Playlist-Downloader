#!/bin/bash
echo "Building Tak Playlist Downloader for Linux..."
echo ""

# Install dependencies
pip3 install --user schedule pystray pillow pyinstaller

# Clean previous build
rm -rf build dist *.spec

# Build executable
pyinstaller --onefile --windowed \
    --name "Tak-Playlist-Downloader" \
    --hidden-import=schedule \
    --hidden-import=pystray \
    --hidden-import=PIL \
    "Tak-Playlist-Downloader.py"

echo ""
echo "Build complete! Executable is in the 'dist' folder."
chmod +x dist/Tak-Playlist-Downloader