@echo off
setlocal enabledelayedexpansion

:: ========== DEFAULT CONFIGURATION ==========
set "OUTPUT_DIR=%CD%"
set "FORMAT=mp3"
:: ===========================================

:: Parse arguments
:parse_args
if "%~1"=="" goto :check_args
if /i "%~1"=="-o" set "OUTPUT_DIR=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-f" set "FORMAT=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-h" goto :show_help
shift
goto :parse_args

:check_args
cd /d "%OUTPUT_DIR%"

set "ARCHIVE_DIR=archive_recovered"

if not exist "%ARCHIVE_DIR%" (
    echo Archive directory not found: %ARCHIVE_DIR%
    pause
    exit /b 0
)

echo Processing recovered files...
echo Source: %ARCHIVE_DIR%
echo Destination: %OUTPUT_DIR%
echo.

set /a MOVED=0
set /a CONVERTED=0

for %%f in ("%ARCHIVE_DIR%\*") do (
    set "filename=%%~nxf"
    set "ext=%%~xf"
    set "ext=!ext:~1!"
    set "name=%%~nf"
    
    echo Processing: !filename!
    
    if /i "!ext!"=="%FORMAT%" (
        move "%%f" "%OUTPUT_DIR%\" >nul 2>nul
        if !errorlevel! equ 0 (
            echo   [OK] Moved
            set /a MOVED+=1
        )
    ) else (
        :: Convert to target format using ffmpeg
        if "%FORMAT%"=="mp3" (
            ffmpeg -i "%%f" -vn -ar 44100 -ac 2 -b:a 192k "%OUTPUT_DIR%\!name!.%FORMAT%" -y >nul 2>nul
            if !errorlevel! equ 0 (
                echo   [OK] Converted to %FORMAT%
                del "%%f" >nul 2>nul
                set /a CONVERTED+=1
            )
        )
    )
)

:: Clean up empty directory
rmdir "%ARCHIVE_DIR%" 2>nul

echo.
echo =========================================
echo PROCESSING COMPLETE
echo =========================================
echo Moved: %MOVED%
echo Converted: %CONVERTED%
echo Files saved to: %OUTPUT_DIR%
pause
exit /b 0

:show_help
echo Usage: %~nx0 [-o OUTPUT_DIR] [-f FORMAT] [-h]
echo.
echo Options:
echo   -o DIR        Output directory (default: current directory)
echo   -f FORMAT     Target format: mp3, mp4 (default: mp3)
echo   -h            Show this help
exit /b 0
