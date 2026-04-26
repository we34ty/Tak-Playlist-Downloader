@echo off
setlocal enabledelayedexpansion

:: ========== DEFAULT CONFIGURATION ==========
set "OUTPUT_DIR=%CD%"
set "SLEEP_INTERVAL=11"
set "FORMAT=mp3"
:: ===========================================

:: Parse arguments
:parse_args
if "%~1"=="" goto :check_args
if /i "%~1"=="-o" set "OUTPUT_DIR=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-t" set "SLEEP_INTERVAL=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-f" set "FORMAT=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-h" goto :show_help
shift
goto :parse_args

:check_args
cd /d "%OUTPUT_DIR%"

set "FAILED_LOG=failed_ids.txt"
set "DOWNLOADED_LOG=downloaded_ids.txt"
set "RECOVERED_LOG=recovered_ids.txt"

if not exist "%FAILED_LOG%" (
    echo No failed_ids.txt found. Nothing to retry.
    pause
    exit /b 1
)

:: Validate format
if "%FORMAT%"=="mp3" set "YTDLP_ARGS=-f ba -x --audio-format mp3"
if "%FORMAT%"=="mp4" set "YTDLP_ARGS=-f bestvideo+bestaudio --merge-output-format mp4"

echo Retrying failed downloads...
echo.

set /a TOTAL=0
for /f %%a in ('type "%FAILED_LOG%" ^| find /c /v ""') do set /a TOTAL=%%a

set /a CURRENT=0
set /a SUCCESS=0
set /a STILL_FAILED=0

for /f "usebackq delims=" %%v in ("%FAILED_LOG%") do (
    set /a CURRENT+=1
    set "video_id=%%v"
    echo [!CURRENT!/%TOTAL%] RETRYING: !video_id!
    
    :: Check if already downloaded
    findstr /x "!video_id!" "%DOWNLOADED_LOG%" >nul 2>nul
    if !errorlevel! equ 0 (
        echo   SKIP: already downloaded
        goto :skip_retry
    )
    
    :: Try YouTube again
    yt-dlp --cookies-from-browser firefox %YTDLP_ARGS% --embed-thumbnail --add-metadata --output "%%(uploader)s - %%(title)s.%%(ext)s" --no-overwrites --continue "https://youtube.com/watch?v=!video_id!" >nul 2>nul
    
    if !errorlevel! equ 0 (
        echo   [OK] Downloaded successfully
        echo !video_id! >> "%DOWNLOADED_LOG%"
        set /a SUCCESS+=1
        :: Remove from failed list
        findstr /v /x "!video_id!" "%FAILED_LOG%" > "%FAILED_LOG%.tmp"
        move /y "%FAILED_LOG%.tmp" "%FAILED_LOG%" >nul 2>nul
    ) else (
        echo   [FAILED] Still unavailable
        set /a STILL_FAILED+=1
    )
    
    :skip_retry
    if %SLEEP_INTERVAL% gtr 0 (
        if !CURRENT! lss %TOTAL% (
            timeout /t %SLEEP_INTERVAL% /nobreak >nul
        )
    )
)

echo.
echo =========================================
echo RETRY COMPLETE
echo =========================================
echo Successfully downloaded: %SUCCESS%
echo Still failed: %STILL_FAILED%
pause
exit /b 0

:show_help
echo Usage: %~nx0 [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-h]
echo.
echo Options:
echo   -o DIR        Output directory (default: current directory)
echo   -t SECONDS    Sleep between retries (default: 11)
echo   -f FORMAT     Output format: mp3, mp4 (default: mp3)
echo   -h            Show this help
exit /b 0
