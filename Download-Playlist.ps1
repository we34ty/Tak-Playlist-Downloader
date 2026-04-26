#!/usr/bin/env pwsh
# ========== DEFAULT CONFIGURATION ==========
param(
    [Parameter(Mandatory=$true)]
    [string]$p,  # Playlist URL
    
    [string]$o = (Get-Location).Path,  # Output directory
    [int]$t = 11,                       # Sleep interval in seconds
    [string]$f = "mp3",                 # Format (mp3, m4a, opus, mp4, webm)
    [string]$q = "mid",                 # Quality (low, mid, high)
    [switch]$h                          # Help
)
# ===========================================

# Colors
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$CYAN = "`e[36m"
$MAGENTA = "`e[35m"
$NC = "`e[0m"

# Help function
if ($h) {
    Write-Host "Usage: .\Download-Playlist.ps1 -p PLAYLIST_URL [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-q QUALITY] [-h]"
    Write-Host ""
    Write-Host "Required:"
    Write-Host "  -p URL        YouTube playlist URL"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -o DIR        Output directory (default: current directory)"
    Write-Host "  -t SECONDS    Sleep between downloads (default: 11)"
    Write-Host "  -f FORMAT     Output format: mp3, m4a, opus, flac, mp4, webm (default: mp3)"
    Write-Host "  -q QUALITY    Quality: low, mid, high (default: mid)"
    Write-Host "                Audio: low(80k), mid(192k), high(320k)"
    Write-Host "                Video: low(worst), mid(480p), high(best)"
    Write-Host "  -h            Show this help"
    exit 0
}

# Validate required parameter
if (-not $p) {
    Write-Host "${RED}ERROR: Playlist URL is required${NC}"
    exit 1
}

# Validate quality
if ($q -notin @("low", "mid", "high")) {
    Write-Host "${RED}ERROR: Quality must be low, mid, or high${NC}"
    exit 1
}

# Clean URL (remove si parameter)
$PLAYLIST_URL = $p -replace '&si=[^&]*', '' -replace '\?si=[^&]*', ''

# Validate sleep interval
if ($t -notmatch '^\d+$') {
    Write-Host "${RED}ERROR: Sleep interval must be a number${NC}"
    exit 1
}

# Set format parameters
$FORMAT_LOWER = $f.ToLower()
$AUDIO_FORMATS = @("mp3", "m4a", "aac", "flac", "wav", "opus")
$VIDEO_FORMATS = @("mp4", "webm", "mkv", "avi", "mov")

if ($AUDIO_FORMATS -contains $FORMAT_LOWER) {
    $DOWNLOAD_TYPE = "audio"
    $OUTPUT_TEMPLATE = "%(uploader)s - %(title)s.%(ext)s"
    Write-Host "${BLUE}Format: $FORMAT_LOWER (audio only)${NC}"
    
    # Set audio quality
    switch ($q) {
        "low" { $AUDIO_QUALITY = "5" }
        "mid" { $AUDIO_QUALITY = "2" }
        "high" { $AUDIO_QUALITY = "0" }
        default { $AUDIO_QUALITY = "2" }
    }
    $YTDLP_ARGS = "-f bestaudio -x --audio-format $FORMAT_LOWER --audio-quality $AUDIO_QUALITY"
    Write-Host "${BLUE}Audio quality: $q ($FORMAT_LOWER)${NC}"
}
elseif ($VIDEO_FORMATS -contains $FORMAT_LOWER) {
    $DOWNLOAD_TYPE = "video"
    $OUTPUT_TEMPLATE = "%(uploader)s - %(title)s.%(ext)s"
    Write-Host "${BLUE}Format: $FORMAT_LOWER (video + audio)${NC}"
    
    # Set video quality
    switch ($q) {
        "low" { $YTDLP_ARGS = "-f worstvideo+worstaudio --merge-output-format $FORMAT_LOWER" }
        "mid" { $YTDLP_ARGS = "-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format $FORMAT_LOWER" }
        "high" { $YTDLP_ARGS = "-f bestvideo+bestaudio --merge-output-format $FORMAT_LOWER" }
        default { $YTDLP_ARGS = "-f bestvideo+bestaudio --merge-output-format $FORMAT_LOWER" }
    }
    Write-Host "${BLUE}Video quality: $q${NC}"
}
else {
    Write-Host "${RED}ERROR: Unsupported format '$FORMAT'${NC}"
    exit 1
}

# Create output directory
if (-not (Test-Path $o)) {
    New-Item -ItemType Directory -Path $o -Force | Out-Null
}
Set-Location $o

# Set up hidden log files
$LOG_FILE = ".downloaded_ids.txt"
$FAILED_LOG = ".failed_ids.txt"
$PERMANENTLY_FAILED_LOG = ".permanently_failed_ids.txt"
$VIDEO_IDS_FILE = ".playlist_videos.txt"
$YTDLP_ARCHIVE = ".ytdlp_archive.txt"

# Initialize files
@() | Out-File -FilePath $LOG_FILE -ErrorAction SilentlyContinue
@() | Out-File -FilePath $FAILED_LOG -ErrorAction SilentlyContinue
@() | Out-File -FilePath $PERMANENTLY_FAILED_LOG -ErrorAction SilentlyContinue
@() | Out-File -FilePath $YTDLP_ARCHIVE -ErrorAction SilentlyContinue

# Internet connection check function
function Check-Internet {
    try {
        $null = ping -n 1 8.8.8.8 -W 2000 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
        $null = ping -n 1 1.1.1.1 -W 2000 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
        $null = Invoke-WebRequest -Uri "https://www.google.com" -TimeoutSec 3 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($?) { return $true }
        return $false
    }
    catch { return $false }
}

function Wait-ForInternet {
    $wait_time = 30
    $elapsed = 0
    
    Write-Host "${YELLOW}⚠️  No internet connection detected${NC}"
    Write-Host "${YELLOW}Waiting for connection to resume...${NC}"
    
    while (-not (Check-Internet)) {
        Start-Sleep -Seconds $wait_time
        $elapsed += $wait_time
        Write-Host "${BLUE}  Still waiting... (${elapsed}s elapsed)${NC}"
    }
    
    Write-Host "${GREEN}✓ Internet connection restored! Resuming downloads.${NC}"
    Start-Sleep -Seconds 5
}

# Functions
function Mark-Downloaded {
    param([string]$video_id)
    Add-Content -Path $LOG_FILE -Value $video_id
    Add-Content -Path $YTDLP_ARCHIVE -Value "youtube $video_id"
}

function Mark-PermanentlyFailed {
    param([string]$video_id)
    Add-Content -Path $PERMANENTLY_FAILED_LOG -Value $video_id
}

# Extract video IDs
Write-Host "${GREEN}=========================================${NC}"
Write-Host "${GREEN}Tak Playlist Downloader (PowerShell)${NC}"
Write-Host "${GREEN}=========================================${NC}"
Write-Host "Output directory: $o"
Write-Host "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
Write-Host "Quality: $q"
Write-Host "Delay: ${t}s"
Write-Host ""

# Check internet
if (-not (Check-Internet)) {
    Wait-ForInternet
}

Write-Host "${BLUE}Fetching playlist...${NC}"

# Extract video IDs
yt-dlp --cookies-from-browser firefox --flat-playlist --print "%(id)s" $PLAYLIST_URL 2>$null | Out-File -FilePath $VIDEO_IDS_FILE

$ids = Get-Content $VIDEO_IDS_FILE | Where-Object { $_ -match '^[a-zA-Z0-9_-]+$' }

if ($ids.Count -eq 0) {
    Write-Host "${RED}ERROR: Could not extract video IDs${NC}"
    exit 1
}

$TOTAL = $ids.Count

# Count downloaded
$DOWNLOADED_COUNT = 0
$PERMANENTLY_FAILED_COUNT = 0
foreach ($id in $ids) {
    if (Select-String -Path $LOG_FILE -Pattern "^$id$" -Quiet -ErrorAction SilentlyContinue) {
        $DOWNLOADED_COUNT++
    }
    elseif (Select-String -Path $PERMANENTLY_FAILED_LOG -Pattern "^$id$" -Quiet -ErrorAction SilentlyContinue) {
        $PERMANENTLY_FAILED_COUNT++
    }
}

$REMAINING = $TOTAL - $DOWNLOADED_COUNT - $PERMANENTLY_FAILED_COUNT
if ($REMAINING -lt 0) { $REMAINING = 0 }

Write-Host "Total videos: $TOTAL"
Write-Host "Already downloaded: $DOWNLOADED_COUNT"
Write-Host "Permanently failed: $PERMANENTLY_FAILED_COUNT"
Write-Host "Remaining: $REMAINING"
Write-Host ""

# Download loop
$PROCESSED = 0
$YOUTUBE_SUCCESS = 0
$FAILED_VIDEOS = 0
$SKIPPED_ALREADY = 0

foreach ($video_id in $ids) {
    $PROCESSED++
    
    # Check if already permanently failed
    if (Select-String -Path $PERMANENTLY_FAILED_LOG -Pattern "^$video_id$" -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "[$($PROCESSED.ToString().PadLeft(4))/$TOTAL] SKIP: $video_id (permanently failed)"
        $SKIPPED_ALREADY++
        continue
    }
    
    # Check if already downloaded
    if (Select-String -Path $LOG_FILE -Pattern "^$video_id$" -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "[$($PROCESSED.ToString().PadLeft(4))/$TOTAL] SKIP: $video_id (already downloaded)"
        $SKIPPED_ALREADY++
        continue
    }
    
    Write-Host ""
    Write-Host "${YELLOW}[$($PROCESSED.ToString().PadLeft(4))/$TOTAL] DOWNLOADING: $video_id${NC}"
    
    if (-not (Check-Internet)) {
        Wait-ForInternet
    }
    
    # Download using yt-dlp
    $download_cmd = "yt-dlp --cookies-from-browser firefox --extractor-args youtubetab:skip=authcheck --download-archive `"$YTDLP_ARCHIVE`" $YTDLP_ARGS --embed-thumbnail --add-metadata --output `"$OUTPUT_TEMPLATE`" --no-overwrites --continue https://youtube.com/watch?v=$video_id 2>`$null"
    Invoke-Expression $download_cmd
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "${GREEN}  ✓ Success - added to log${NC}"
        Mark-Downloaded $video_id
        $YOUTUBE_SUCCESS++
    }
    else {
        Write-Host "${RED}  ✗ YouTube failed${NC}"
        Write-Host "${YELLOW}  → Archive recovery not available in Windows version${NC}"
        Mark-PermanentlyFailed $video_id
        $FAILED_VIDEOS++
    }
    
    # Delay between downloads
    if ($t -gt 0 -and $PROCESSED -lt $TOTAL) {
        Write-Host "${BLUE}  Waiting ${t}s...${NC}"
        Start-Sleep -Seconds $t
    }
}

# Summary
Write-Host ""
Write-Host "${GREEN}=========================================${NC}"
Write-Host "${GREEN}COMPLETE!${NC}"
Write-Host "${GREEN}=========================================${NC}"
Write-Host "Total videos: $TOTAL"
Write-Host ""
Write-Host "${GREEN}✓ Downloaded: $YOUTUBE_SUCCESS${NC}"
Write-Host "${BLUE}○ Skipped (already in log): $SKIPPED_ALREADY${NC}"
Write-Host "${RED}✗ Failed: $FAILED_VIDEOS${NC}"
Write-Host ""
Write-Host "Files saved to: $o"
