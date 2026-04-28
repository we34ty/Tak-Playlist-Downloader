@echo off
echo Building Tak Playlist Downloader for Windows...
echo.

REM Install dependencies
pip install schedule pystray pillow pyinstaller

REM Clean previous build
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist *.spec del *.spec

REM Build executable
pyinstaller --onefile --windowed ^
    --name "Tak-Playlist-Downloader" ^
    --hidden-import=schedule ^
    --hidden-import=pystray ^
    --hidden-import=PIL ^
    --add-data "Download-Playlist.ps1;." ^
    --add-data "Retry-Failed.ps1;." ^
    --add-data "Move-Recovered.ps1;." ^
    Tak-Playlist-Downloader.py

echo.
echo Build complete! Executable is in the 'dist' folder.
pause