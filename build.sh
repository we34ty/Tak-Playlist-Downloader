#!/bin/bash

echo "========================================"
echo "Tak Playlist Downloader - Build Script"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running with appropriate privileges
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Note: Running as root. This is not necessary for building.${NC}"
fi

echo "Checking Python installation..."
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[ERROR] Python 3 not found!${NC}"
    echo ""
    echo "Please install Python 3.8 or higher:"
    echo "  Ubuntu/Debian: sudo apt install python3 python3-pip python3-venv python3-tk"
    echo "  Fedora: sudo dnf install python3 python3-pip python3-tkinter"
    echo "  Arch: sudo pacman -S python python-pip tk"
    exit 1
fi

python3 --version
echo ""

echo "Checking for tkinter..."
python3 -c "import tkinter" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Tkinter not found!${NC}"
    echo ""
    echo "Please install tkinter:"
    echo "  Ubuntu/Debian: sudo apt install python3-tk"
    echo "  Fedora: sudo dnf install python3-tkinter"
    echo "  Arch: sudo pacman -S tk"
    exit 1
fi
echo -e "${GREEN}✓ Tkinter found${NC}"
echo ""

echo "Creating virtual environment..."
if [ ! -d "build_env" ]; then
    python3 -m venv build_env
fi

echo "Activating virtual environment..."
source build_env/bin/activate

echo "Installing packages..."
pip install --upgrade pip >/dev/null 2>&1
pip install schedule
pip install pystray
pip install pillow
pip install pyinstaller
pip install ttkthemes

echo ""
echo "Building executable..."
echo "This may take a few minutes..."
echo ""

# Clean previous build
rm -rf build dist *.spec 2>/dev/null

# Build the executable
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
    --hidden-import=getpass \
    --collect-all schedule \
    --collect-all pystray \
    Tak-Playlist-Downloader.py

if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}[ERROR] Build failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================"
echo "BUILD SUCCESSFUL!"
echo "========================================${NC}"
echo ""
echo "Executable: dist/Tak-Playlist-Downloader"
echo "Size: $(du -h dist/Tak-Playlist-Downloader | cut -f1)"
echo ""

# Make executable
chmod +x dist/Tak-Playlist-Downloader

# Copy required scripts
echo "Copying required shell scripts..."
if [ -f "Download-Playlist.sh" ]; then
    cp Download-Playlist.sh dist/
    echo -e "${GREEN}  ✓ Download-Playlist.sh${NC}"
else
    echo -e "${RED}  ✗ Download-Playlist.sh not found!${NC}"
fi

if [ -f "Retry-Failed.sh" ]; then
    cp Retry-Failed.sh dist/
    echo -e "${GREEN}  ✓ Retry-Failed.sh${NC}"
else
    echo -e "${RED}  ✗ Retry-Failed.sh not found!${NC}"
fi

if [ -f "Move-Recovered.sh" ]; then
    cp Move-Recovered.sh dist/
    echo -e "${GREEN}  ✓ Move-Recovered.sh${NC}"
else
    echo -e "${RED}  ✗ Move-Recovered.sh not found!${NC}"
fi

echo ""
echo "All done! The executable is in the 'dist' folder."
echo ""
echo "To run: ./dist/Tak-Playlist-Downloader"
echo ""

# Deactivate virtual environment
deactivate

echo -e "${GREEN}Build process completed.${NC}"