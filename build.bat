@echo off
title Tak Playlist Downloader - Build Script
echo ========================================
echo Tak Playlist Downloader - Build Script
echo ========================================
echo.

REM Check if running as administrator (optional, for convenience)
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Running with administrator privileges.
) else (
    echo Note: Running without administrator privileges. This is fine for building.
)

echo Checking Python installation...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found!
    echo.
    echo Please install Python 3.8 or higher from:
    echo https://www.python.org/downloads/
    echo.
    echo Make sure to check "Add Python to PATH" during installation.
    echo Also ensure "tcl/tk" is checked (for tkinter).
    pause
    exit /b 1
)

python --version
echo.

echo Checking for tkinter...
python -c "import tkinter" 2>nul
if errorlevel 1 (
    echo [WARNING] Tkinter not found!
    echo On Windows, tkinter is included with Python by default.
    echo If you continue, the GUI may not work properly.
    echo.
    choice /C YN /M "Continue anyway?"
    if errorlevel 2 exit /b 1
)

echo.
echo Installing/updating required packages...
echo.

REM Create virtual environment
if not exist "build_env" (
    echo Creating virtual environment...
    python -m venv build_env
)

echo Activating virtual environment...
call build_env\Scripts\activate.bat

echo Installing packages...
pip install --upgrade pip >nul
pip install schedule
pip install pystray
pip install pillow
pip install pyinstaller
pip install ttkthemes

echo.
echo Building executable...
echo This may take a few minutes...
echo.

REM Clean previous build
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist *.spec del *.spec

REM Build the executable
pyinstaller --onefile --windowed ^
    --name "Tak-Playlist-Downloader" ^
    --icon=NONE ^
    --hidden-import=schedule ^
    --hidden-import=pystray ^
    --hidden-import=PIL ^
    --hidden-import=PIL.Image ^
    --hidden-import=PIL.ImageDraw ^
    --hidden-import=tkinter ^
    --hidden-import=threading ^
    --hidden-import=subprocess ^
    --hidden-import=json ^
    --hidden-import=datetime ^
    --hidden-import=pathlib ^
    --hidden-import=uuid ^
    --hidden-import=queue ^
    --hidden-import=atexit ^
    --hidden-import=getpass ^
    --collect-all schedule ^
    --collect-all pystray ^
    Tak-Playlist-Downloader.py

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Build failed!
    pause
    exit /b %errorLevel%
)

echo.
echo ========================================
echo BUILD SUCCESSFUL!
echo ========================================
echo.
echo Executable: dist\Tak-Playlist-Downloader.exe
echo Size: 
dir dist\Tak-Playlist-Downloader.exe | find "Tak-Playlist-Downloader.exe"
echo.

REM Copy required scripts
echo Copying required PowerShell scripts...
if exist "Download-Playlist.ps1" (
    copy /Y Download-Playlist.ps1 dist\ >nul
    echo   - Download-Playlist.ps1
) else (
    echo   [WARNING] Download-Playlist.ps1 not found!
)

if exist "Retry-Failed.ps1" (
    copy /Y Retry-Failed.ps1 dist\ >nul
    echo   - Retry-Failed.ps1
) else (
    echo   [WARNING] Retry-Failed.ps1 not found!
)

if exist "Move-Recovered.ps1" (
    copy /Y Move-Recovered.ps1 dist\ >nul
    echo   - Move-Recovered.ps1
) else (
    echo   [WARNING] Move-Recovered.ps1 not found!
)

echo.
echo All done! The executable is in the 'dist' folder.
echo.
echo To run: double-click Tak-Playlist-Downloader.exe
echo.
echo Deactivating virtual environment...
call build_env\Scripts\deactivate.bat

echo.
pause