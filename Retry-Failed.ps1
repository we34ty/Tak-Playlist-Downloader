#!/usr/bin/env pwsh
# ========== DEFAULT CONFIGURATION ==========
param(
    [string]$o = (Get-Location).Path,  # Output directory
    [int]$t = 11,                       # Sleep interval
    [string]$f = "mp3",                 # Format
    [string]$q = "mid",                 # Quality
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
    Write-Host "Usage: .\Retry-Failed.ps1 [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-q QUALITY] [-h]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -o DIR        Output directory (default: current directory)"
    Write-Host "  -t SECONDS    Sleep interval between retries (default: 11)"
    Write-Host "  -f FORMAT     Output format (default: mp3)"
    Write-Host "  -q QUALITY    Quality: low, mid, high (default: mid)"
    Write-Host "  -h            Show this help message"
    Write-Host ""
    Write-Host "Note: Archive recovery is not available in Windows version"
    exit 0
}

# Validate quality
if ($q -notin @("low", "mid", "high")) {
    Write-Host "${RED}ERROR: Quality must be low, mid, or high${NC}"
    exit 1
}

# Validate sleep interval
if ($t -notmatch '^\d+$') {
    Write-Host "${RED}ERROR: Sleep interval must be a number${NC}"
    exit 1
}

# Validate format
$FORMAT_LOWER = $f.ToLower()
$AUDIO_FORMATS = @("mp3", "m4a", "aac", "flac", "wav", "opus")
$VIDEO_FORMATS = @("mp4", "webm", "mkv", "avi", "mov")

if ($AUDIO_FORMATS -contains $FORMAT_LOWER) {
    $DOWNLOAD_TYPE = "audio"
    $OUTPUT_TEMPLATE = "%(uploader)s - %(title)s.%(ext)s"
    Write-Host "${BLUE}Format: $FORMAT_LOWER (audio only)${NC}"
    
    switch ($q) {
        "low" { $AUDIO_QUALITY = "5" }
        "mid" { $AUDIO_QUALITY = "2" }
        "high" { $AUDIO_QUALITY = "0" }
        default { $AUDIO_QUALITY = "2" }
    }
    $YTDLP_ARGS = "-f bestaudio -x --audio-format $FORMAT_LOWER --audio-quality $AUDIO_QUALITY"
}
elseif ($VIDEO_FORMATS -contains $FORMAT_LOWER) {
    $DOWNLOAD_TYPE = "video"
    $OUTPUT_TEMPLATE = "%(uploader)s - %(title)s.%(ext)s"
    Write-Host "${BLUE}Format: $FORMAT_LOWER (video + audio)${NC}"
    
    switch ($q) {
        "low" { $YTDLP_ARGS = "-f worstvideo+worstaudio --merge-output-format $FORMAT_LOWER" }
        "mid" { $YTDLP_ARGS = "-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format $FORMAT_LOWER" }
        "high" { $YTDLP_ARGS = "-f bestvideo+bestaudio --merge-output-format $FORMAT_LOWER" }
        default { $YTDLP_ARGS = "-f bestvideo+bestaudio --merge-output-format $FORMAT_LOWER" }
    }
}
else {
    Write-Host "${RED}ERROR: Unsupported format '$FORMAT'${NC}"
    exit 1
}

Write-Host "${BLUE}Quality: $q (forcing ${FORMAT_LOWER} conversion)${NC}"

# Change to output directory
if (-not (Test-Path $o)) {
    Write-Host "${RED}ERROR: Output directory not found: $o${NC}"
    exit 1
}
Set-Location $o

# Set up hidden file paths
$DOWNLOADED_LOG = ".downloaded_ids.txt"
$FAILED_LOG = ".failed_ids.txt"
$PERMANENTLY_FAILED_LOG = ".permanently_failed_ids.txt"
$RECOVERED_LOG = ".recovered_ids.txt"
$YTDLP_ARCHIVE = ".ytdlp_archive.txt"

# Internet check function
function Check-Internet {
    try {
        $null = ping -n 1 8.8.8.8 -W 2000 2>$null
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
    
    Write-Host "${GREEN}✓ Internet connection restored! Resuming.${NC}"
    Start-Sleep -Seconds 5
}

# Functions
function Mark-Downloaded {
    param([string]$video_id)
    Add-Content -Path $DOWNLOADED_LOG -Value $video_id
    Add-Content -Path $YTDLP_ARCHIVE -Value "youtube $video_id"
}

function Mark-PermanentlyFailed {
    param([string]$video_id)
    Add-Content -Path $PERMANENTLY_FAILED_LOG -Value $video_id
}

function Remove-FromFailed {
    param([string]$video_id)
    $content = Get-Content $FAILED_LOG -ErrorAction SilentlyContinue | Where-Object { $_ -ne $video_id }
    $content | Out-File -FilePath $FAILED_LOG -Force
}

# Main retry loop
Write-Host "${GREEN}=========================================${NC}"
Write-Host "${GREEN}Retry Failed Downloads (PowerShell)${NC}"
Write-Host "${GREEN}=========================================${NC}"
Write-Host "Output directory: $o"
Write-Host "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
Write-Host "Quality: $q"
Write-Host "Delay between retries: ${t}s"
Write-Host ""

if (-not (Test-Path $FAILED_LOG) -or (Get-Content $FAILED_LOG -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
    Write-Host "${YELLOW}No .failed_ids.txt found or it's empty. Nothing to retry.${NC}"
    exit 1
}

if (-not (Check-Internet)) {
    Wait-ForInternet
}

# Filter out already downloaded or permanently failed
$failed_ids = Get-Content $FAILED_LOG | Where-Object { $_ -match '^[a-zA-Z0-9_-]+$' }
$to_retry = @()

foreach ($video_id in $failed_ids) {
    if (Select-String -Path $PERMANENTLY_FAILED_LOG -Pattern "^$video_id$" -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "${CYAN}  Skipping permanently failed: $video_id${NC}"
        Remove-FromFailed $video_id
    }
    elseif (Select-String -Path $DOWNLOADED_LOG -Pattern "^$video_id$" -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "${CYAN}  Skipping already downloaded: $video_id${NC}"
        Remove-FromFailed $video_id
    }
    else {
        $to_retry += $video_id
    }
}

$TOTAL = $to_retry.Count

if ($TOTAL -eq 0) {
    Write-Host "${GREEN}All failed videos have been marked as permanently failed!${NC}"
    exit 0
}

Write-Host "${CYAN}Videos to retry: $TOTAL${NC}"
Write-Host ""

$CURRENT = 0
$SUCCESS = 0
$STILL_FAILED = 0

foreach ($video_id in $to_retry) {
    $CURRENT++
    Write-Host ""
    Write-Host "${YELLOW}[$CURRENT/$TOTAL] RETRYING: $video_id${NC}"
    
    if (-not (Check-Internet)) {
        Wait-ForInternet
    }
    
    Write-Host "${BLUE}  → Trying YouTube...${NC}"
    $download_cmd = "yt-dlp --cookies-from-browser firefox --extractor-args youtubetab:skip=authcheck --download-archive `"$YTDLP_ARCHIVE`" $YTDLP_ARGS --embed-thumbnail --add-metadata --output `"$OUTPUT_TEMPLATE`" --no-overwrites --continue https://youtube.com/watch?v=$video_id 2>`$null"
    Invoke-Expression $download_cmd
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "${GREEN}  ✓ Downloaded successfully${NC}"
        Mark-Downloaded $video_id
        Remove-FromFailed $video_id
        $SUCCESS++
    }
    else {
        Write-Host "${RED}  ✗ Still unavailable on YouTube${NC}"
        Write-Host "${YELLOW}  → Archive recovery not available in Windows version${NC}"
        Write-Host "${YELLOW}  → Marked as permanently failed${NC}"
        Mark-PermanentlyFailed $video_id
        Remove-FromFailed $video_id
        $STILL_FAILED++
    }
    
    if ($CURRENT -lt $TOTAL) {
        Write-Host "${BLUE}  Waiting ${t}s...${NC}"
        Start-Sleep -Seconds $t
    }
}

# Summary
Write-Host ""
Write-Host "${GREEN}=========================================${NC}"
Write-Host "${GREEN}RETRY COMPLETE${NC}"
Write-Host "${GREEN}=========================================${NC}"
Write-Host "${GREEN}✓ Downloaded from YouTube: $SUCCESS${NC}"
Write-Host "${RED}✗ Permanently failed: $STILL_FAILED${NC}"
Write-Host ""
Write-Host "Permanently failed videos saved to: $PERMANENTLY_FAILED_LOG"
