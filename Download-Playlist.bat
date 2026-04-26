@echo off
setlocal enabledelayedexpansion

:: ========== DEFAULT CONFIGURATION ==========
set "OUTPUT_DIR=%CD%"
set "SLEEP_INTERVAL=11"
set "ENABLE_ARCHIVE=false"
set "PLAYLIST_URL="
set "FORMAT=mp3"
:: ===========================================

:: Parse arguments
:parse_args
if "%~1"=="" goto :check_args
if /i "%~1"=="-p" set "PLAYLIST_URL=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-o" set "OUTPUT_DIR=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-t" set "SLEEP_INTERVAL=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-f" set "FORMAT=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-a" set "ENABLE_ARCHIVE=true" & shift & goto :parse_args
if /i "%~1"=="-h" goto :show_help
shift
goto :parse_args

:check_args
if "%PLAYLIST_URL%"=="" (
    echo [ERROR] Playlist URL is required
    goto :show_help
)

:: Validate format
if "%FORMAT%"=="mp3" set "YTDLP_ARGS=-f ba -x --audio-format mp3"
if "%FORMAT%"=="mp4" set "YTDLP_ARGS=-f bestvideo+bestaudio --merge-output-format mp4"
if "%FORMAT%"=="opus" set "YTDLP_ARGS=-f ba -x --audio-format opus"
if "%FORMAT%"=="m4a" set "YTDLP_ARGS=-f ba -x --audio-format m4a"

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
cd /d "%OUTPUT_DIR%"

:: Set log files
set "LOG_FILE=downloaded_ids.txt"
set "FAILED_LOG=failed_ids.txt"
set "RECOVERED_LOG=recovered_ids.txt"
set "VIDEO_IDS_FILE=playlist_videos.txt"

:: Extract video IDs from playlist
echo Fetching playlist...
yt-dlp --cookies-from-browser firefox --flat-playlist --print "%%(id)s" "%PLAYLIST_URL%" > "%VIDEO_IDS_FILE%" 2>nul

if not exist "%VIDEO_IDS_FILE%" (
    echo [ERROR] Could not extract video IDs
    exit /b 1
)

:: Count total videos
set /a TOTAL=0
for /f %%a in ('type "%VIDEO_IDS_FILE%" ^| find /c /v ""') do set /a TOTAL=%%a

echo Total videos: %TOTAL%
echo.

:: Download loop
set /a PROCESSED=0
set /a YOUTUBE_SUCCESS=0
set /a FAILED_VIDEOS=0

for /f "usebackq delims=" %%v in ("%VIDEO_IDS_FILE%") do (
    set /a PROCESSED+=1
    set "video_id=%%v"
    echo [!PROCESSED!/%TOTAL%] DOWNLOADING: !video_id!
    
    :: Check if already downloaded
    findstr /x "!video_id!" "%LOG_FILE%" >nul 2>nul
    if !errorlevel! equ 0 (
        echo   SKIP: already downloaded
        goto :skip_download
    )
    
    :: Download from YouTube
    yt-dlp --cookies-from-browser firefox %YTDLP_ARGS% --embed-thumbnail --add-metadata --output "%%(uploader)s - %%(title)s.%%(ext)s" --no-overwrites --continue "https://youtube.com/watch?v=!video_id!" >nul 2>nul
    
    if !errorlevel! equ 0 (
        echo   [OK] Downloaded successfully
        echo !video_id! >> "%LOG_FILE%"
        set /a YOUTUBE_SUCCESS+=1
    ) else (
        echo   [FAILED] YouTube error
        echo !video_id! >> "%FAILED_LOG%"
        set /a FAILED_VIDEOS+=1
    )
    
    :skip_download
    if %SLEEP_INTERVAL% gtr 0 (
        if !PROCESSED! lss %TOTAL% (
            timeout /t %SLEEP_INTERVAL% /nobreak >nul
        )
    )
)

echo.
echo =========================================
echo DOWNLOAD COMPLETE!
echo =========================================
echo YouTube downloads: %YOUTUBE_SUCCESS%
echo Failed: %FAILED_VIDEOS%
echo Files saved to: %OUTPUT_DIR%
pause
exit /b 0

:show_help
echo Usage: %~nx0 -p PLAYLIST_URL [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-a] [-h]
echo.
echo Required:
echo   -p URL        YouTube playlist URL
echo Options:
echo   -o DIR        Output directory (default: current directory)
echo   -t SECONDS    Sleep between downloads (default: 11)
echo   -f FORMAT     Output format: mp3, mp4, opus, m4a (default: mp3)
echo   -a            Enable archive recovery (not fully implemented on Windows)
echo   -h            Show this help
exit /b 0
