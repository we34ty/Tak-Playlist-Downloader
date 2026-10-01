#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
SLEEP_INTERVAL=11     # Default 11 seconds
FORMAT="mp3"          # Default format
QUALITY="mid"         # Default quality
BROWSER="firefox"     # Default browser
TAK_DATA_DIR=".TakData"
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Function to get TakData directory path
get_takdata_path() {
    local output_dir="$1"
    local takdata_path="${output_dir}/${TAK_DATA_DIR}"
    mkdir -p "$takdata_path"
    echo "$takdata_path"
}

# Internet connection check
check_internet() {
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || \
       ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || \
       curl -s --max-time 3 https://www.google.com >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

wait_for_internet() {
    local wait_time=30
    local elapsed=0
    
    echo -e "${YELLOW}⚠️  No internet connection detected${NC}"
    echo -e "${YELLOW}Waiting for connection to resume...${NC}"
    
    while ! check_internet; do
        sleep "$wait_time"
        elapsed=$((elapsed + wait_time))
        echo -e "${BLUE}  Still waiting... (${elapsed}s elapsed)${NC}"
    done
    
    echo -e "${GREEN}✓ Internet connection restored! Resuming.${NC}"
    sleep 5
}

# Set quality parameters
set_quality_params() {
    local quality="$1"
    local format="$2"
    local format_lower=$(echo "$format" | tr '[:upper:]' '[:lower:]')
    local audio_formats="mp3 m4a aac flac wav opus"
    local video_formats="mp4 webm mkv avi mov"
    
    if echo "$audio_formats" | grep -qw "$format_lower"; then
        case "$quality" in
            low) AUDIO_QUALITY="5" ;;
            mid) AUDIO_QUALITY="2" ;;
            high) AUDIO_QUALITY="0" ;;
            *) AUDIO_QUALITY="2" ;;
        esac
        YTDLP_EXTRA_ARGS="-f bestaudio -x --audio-format ${format_lower} --audio-quality ${AUDIO_QUALITY}"
    else
        case "$quality" in
            low) YTDLP_EXTRA_ARGS="-f worstvideo+worstaudio --merge-output-format ${format_lower}" ;;
            mid) YTDLP_EXTRA_ARGS="-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format ${format_lower}" ;;
            high) YTDLP_EXTRA_ARGS="-f bestvideo+bestaudio --merge-output-format ${format_lower}" ;;
            *) YTDLP_EXTRA_ARGS="-f bestvideo+bestaudio --merge-output-format ${format_lower}" ;;
        esac
    fi
}

# Help function
show_help() {
    echo "Usage: $0 [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-q QUALITY] [-b BROWSER] [-h]"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -t SECONDS    Sleep interval between retries (default: 11)"
    echo "  -f FORMAT     Output format (default: mp3)"
    echo "  -q QUALITY    Quality: low, mid, high (default: mid)"
    echo "  -b BROWSER    Browser for cookies: firefox, chrome, chromium, brave, edge, opera, vivaldi, safari, none (default: firefox)"
    echo "  -h            Show this help message"
    echo ""
    echo "Note: This script shares configuration with Download-Playlist.sh"
    echo "      Settings and logs are stored in '${TAK_DATA_DIR}' subfolder"
}

# Parse arguments
while getopts "o:t:f:q:b:h" opt; do
    case $opt in
        o) OUTPUT_DIR="$OPTARG" ;;
        t) SLEEP_INTERVAL="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        q) QUALITY="$OPTARG" ;;
        b) BROWSER="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Track which arguments were explicitly provided
HAS_O=0
HAS_T=0
HAS_F=0
HAS_Q=0
HAS_B=0

for arg in "$@"; do
    case "$arg" in
        -o) HAS_O=1 ;;
        -t) HAS_T=1 ;;
        -f) HAS_F=1 ;;
        -q) HAS_Q=1 ;;
        -b) HAS_B=1 ;;
    esac
done

# ========== LOAD SAVED CONFIGURATION ==========
TAK_DATA_PATH=$(get_takdata_path "$OUTPUT_DIR")
CONFIG_FILE="${TAK_DATA_PATH}/download_config.json"

if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    echo -e "${BLUE}Loading saved configuration from: $CONFIG_FILE${NC}"
    
    [ $HAS_O -eq 0 ] && OUTPUT_DIR=$(jq -r '.OutputDir' "$CONFIG_FILE")
    [ $HAS_T -eq 0 ] && SLEEP_INTERVAL=$(jq -r '.SleepInterval' "$CONFIG_FILE")
    [ $HAS_F -eq 0 ] && FORMAT=$(jq -r '.Format' "$CONFIG_FILE")
    [ $HAS_Q -eq 0 ] && QUALITY=$(jq -r '.Quality' "$CONFIG_FILE")
    [ $HAS_B -eq 0 ] && BROWSER=$(jq -r '.Browser // "firefox"' "$CONFIG_FILE")
    
    echo -e "${GREEN}[INFO] Using saved settings from: $CONFIG_FILE${NC}"
    echo "  Format: $FORMAT"
    echo "  Quality: $QUALITY"
    echo "  Browser: $BROWSER"
    echo "  Delay: ${SLEEP_INTERVAL}s"
    echo ""
elif [ -f "$CONFIG_FILE" ] && ! command -v jq &>/dev/null; then
    echo -e "${RED}ERROR: jq is required to parse saved configuration${NC}"
    echo "Please install jq: sudo apt install jq"
    exit 1
fi

# Validate quality
if [[ ! "$QUALITY" =~ ^(low|mid|high)$ ]]; then
    echo -e "${RED}ERROR: Quality must be low, mid, or high${NC}"
    exit 1
fi

# Validate sleep interval
if ! [[ "$SLEEP_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Sleep interval must be a number${NC}"
    exit 1
fi

# Validate format
FORMAT_LOWER=$(echo "$FORMAT" | tr '[:upper:]' '[:lower:]')
AUDIO_FORMATS="mp3 m4a aac flac wav opus"
VIDEO_FORMATS="mp4 webm mkv avi mov"

if echo "$AUDIO_FORMATS" | grep -qw "$FORMAT_LOWER"; then
    DOWNLOAD_TYPE="audio"
    OUTPUT_TEMPLATE="%(uploader)s - %(title)s.%(ext)s"
    echo -e "${BLUE}Format: $FORMAT_LOWER (audio only)${NC}"
elif echo "$VIDEO_FORMATS" | grep -qw "$FORMAT_LOWER"; then
    DOWNLOAD_TYPE="video"
    OUTPUT_TEMPLATE="%(uploader)s - %(title)s.%(ext)s"
    echo -e "${BLUE}Format: $FORMAT_LOWER (video + audio)${NC}"
else
    echo -e "${RED}ERROR: Unsupported format '$FORMAT'${NC}"
    exit 1
fi

set_quality_params "$QUALITY" "$FORMAT"
echo -e "${BLUE}Quality: $QUALITY (forcing ${FORMAT_LOWER} conversion)${NC}"

# ========== SAVE CONFIGURATION IF CHANGED ==========
if [ $HAS_F -eq 1 ] || [ $HAS_Q -eq 1 ] || [ $HAS_T -eq 1 ] || [ $HAS_B -eq 1 ]; then
    TAK_DATA_PATH=$(get_takdata_path "$OUTPUT_DIR")
    CONFIG_FILE="${TAK_DATA_PATH}/download_config.json"
    
    # Load existing config to preserve other values
    if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
        PLAYLIST_URL=$(jq -r '.PlaylistUrl' "$CONFIG_FILE")
        ENABLE_ARCHIVE=$(jq -r '.EnableArchive' "$CONFIG_FILE")
    else
        PLAYLIST_URL=""
        ENABLE_ARCHIVE="false"
    fi
    
    cat > "$CONFIG_FILE" << EOF
{
    "PlaylistUrl": "$PLAYLIST_URL",
    "OutputDir": "$OUTPUT_DIR",
    "SleepInterval": $SLEEP_INTERVAL,
    "Format": "$FORMAT",
    "Quality": "$QUALITY",
    "Browser": "$BROWSER",
    "EnableArchive": $ENABLE_ARCHIVE,
    "LastUpdated": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
    echo -e "${BLUE}Configuration updated in: $CONFIG_FILE${NC}"
fi

# ========== CHANGE TO OUTPUT DIRECTORY ==========
cd "$OUTPUT_DIR" || exit 1

# ========== SET UP TAKDATA DIRECTORY AND LOG FILES ==========
TAK_DATA_PATH="${OUTPUT_DIR}/${TAK_DATA_DIR}"
mkdir -p "$TAK_DATA_PATH"

ARCHIVE_DIR="${TAK_DATA_PATH}/archive_recovered"
RECOVERED_LOG="${TAK_DATA_PATH}/recovered_ids.txt"
DOWNLOADED_LOG="${TAK_DATA_PATH}/downloaded_ids.txt"
FAILED_LOG="${TAK_DATA_PATH}/failed_ids.txt"
PERMANENTLY_FAILED_LOG="${TAK_DATA_PATH}/permanently_failed_ids.txt"

mkdir -p "$ARCHIVE_DIR"
touch "$RECOVERED_LOG" "$DOWNLOADED_LOG" "$PERMANENTLY_FAILED_LOG"

echo -e "${BLUE}TakData directory: $TAK_DATA_PATH${NC}"
echo -e "${BLUE}Log files stored in TakData subfolder${NC}"

# Simple mark functions
mark_recovered() { 
    echo "$1" >> "$RECOVERED_LOG"
    sync
}
mark_downloaded() { 
    echo "$1" >> "$DOWNLOADED_LOG"
    sync
}
mark_permanently_failed() { 
    echo "$1" >> "$PERMANENTLY_FAILED_LOG"
    sync
}

remove_from_failed() {
    local video_id="$1"
    grep -Fxv -- "$video_id" "$FAILED_LOG" > "$FAILED_LOG.tmp" 2>/dev/null
    mv "$FAILED_LOG.tmp" "$FAILED_LOG" 2>/dev/null
}

# ============================================================================
# ========== ARCHIVE SEARCH FUNCTIONS (FIXED) ================================
# ============================================================================
# These functions now try multiple URL variants and use the correct APIs:
#   - Wayback: CDX API with matchType=prefix across all YouTube URL forms
#   - Archive.org: Advanced Search API to find items by video ID
#   - GhostArchive: Direct download attempt (no pre-check that can fail on Cloudflare)
# ============================================================================

# Search Wayback Machine using CDX API across multiple URL variants
search_wayback() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}     → Checking Wayback Machine...${NC}"
    
    # Try multiple URL variants since Wayback captures videos under many formats
    local url_variants=(
        "youtube.com/watch?v=${video_id}"
        "www.youtube.com/watch?v=${video_id}"
        "youtu.be/${video_id}"
        "m.youtube.com/watch?v=${video_id}"
        "youtube.com/embed/${video_id}"
        "www.youtube.com/embed/${video_id}"
    )
    
    local found_original=""
    local found_timestamp=""
    local matched_variant=""
    
    for variant in "${url_variants[@]}"; do
        # Query CDX API with matchType=prefix to catch extra query params
        local cdx_url="https://web.archive.org/cdx/search/cdx?url=${variant}&matchType=prefix&output=json&limit=5&fl=timestamp,original,statuscode&filter=statuscode:200"
        
        local cdx_response=$(curl -sL --max-time 20 "$cdx_url" 2>/dev/null)
        
        if [ -n "$cdx_response" ] && [ "$cdx_response" != "[]" ] && [ "$cdx_response" != "null" ]; then
            # Parse JSON: skip header row, get first snapshot
            local parsed=$(echo "$cdx_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if len(data) > 1:
        print(data[1][0] + '|' + data[1][1])
except Exception:
    pass
" 2>/dev/null)
            
            if [ -n "$parsed" ]; then
                found_timestamp=$(echo "$parsed" | cut -d'|' -f1)
                found_original=$(echo "$parsed" | cut -d'|' -f2)
                matched_variant="$variant"
                echo -e "${BLUE}       Matched variant: ${variant}${NC}"
                break
            fi
        fi
    done
    
    if [ -z "$found_timestamp" ] || [ -z "$found_original" ]; then
        echo -e "${RED}     ✗ Not found on Wayback Machine${NC}"
        return 1
    fi
    
    # Build the Wayback URL using the ACTUAL archived original URL
    local wayback_url="https://web.archive.org/web/${found_timestamp}if_/${found_original}"
    
    echo -e "${GREEN}     ✓ Found on Wayback (capture ${found_timestamp})${NC}"
    echo -e "${BLUE}       URL: ${wayback_url}${NC}"
    
    # Try to download
    yt-dlp --no-warnings --no-playlist \
           --no-check-certificate \
           --output "$output_file" \
           "$wayback_url" 2>/dev/null && return 0
    
    return 1
}

# Search GhostArchive (direct download attempt - HEAD check can fail on Cloudflare)
search_ghostarchive() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}     → Checking GhostArchive...${NC}"
    
    local ghost_url="https://ghostarchive.org/varchive/youtube/$video_id"
    
    # Skip the pre-check and just try the download.
    # GhostArchive returns 200 for real videos and 404/redirect for missing ones.
    if yt-dlp --no-warnings --no-playlist \
              --no-check-certificate \
              --socket-timeout 20 \
              --output "$output_file" \
              "$ghost_url" 2>/dev/null; then
        echo -e "${GREEN}     ✓ Downloaded from GhostArchive${NC}"
        return 0
    fi
    
    echo -e "${RED}     ✗ Not found on GhostArchive${NC}"
    return 1
}

# Search Archive.org using Advanced Search API (more reliable than guessing identifier)
search_archive_org() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}     → Checking Archive.org...${NC}"
    
    # First try the common identifier format (fast path)
    local direct_url="https://archive.org/details/youtube-$video_id"
    if yt-dlp --no-warnings --no-playlist \
              --no-check-certificate \
              --socket-timeout 20 \
              -f "bestvideo+bestaudio/best" \
              --output "$output_file" \
              "$direct_url" 2>/dev/null; then
        echo -e "${GREEN}     ✓ Downloaded from Archive.org (direct)${NC}"
        return 0
    fi
    
    # Fallback: search Archive.org for items mentioning the video ID
    local search_url="https://archive.org/advancedsearch.php?q=youtube+${video_id}&fl[]=identifier&rows=5&output=json"
    local search_response=$(curl -sL --max-time 15 "$search_url" 2>/dev/null)
    
    if [ -n "$search_response" ]; then
        local identifier=$(echo "$search_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    docs = data.get('response', {}).get('docs', [])
    for doc in docs:
        ident = doc.get('identifier', '')
        if ident:
            print(ident)
            break
except Exception:
    pass
" 2>/dev/null)
        
        if [ -n "$identifier" ]; then
            local item_url="https://archive.org/details/${identifier}"
            echo -e "${BLUE}       Found Archive.org item: ${identifier}${NC}"
            
            if yt-dlp --no-warnings --no-playlist \
                      --no-check-certificate \
                      --socket-timeout 20 \
                      -f "bestvideo+bestaudio/best" \
                      --output "$output_file" \
                      "$item_url" 2>/dev/null; then
                echo -e "${GREEN}     ✓ Downloaded from Archive.org (search)${NC}"
                return 0
            fi
        fi
    fi
    
    echo -e "${RED}     ✗ Not found on Archive.org${NC}"
    return 1
}

# Search Hobune.stream (direct MP4 file)
search_hobune() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}     → Checking Hobune.stream...${NC}"
    
    local hobune_url="https://hobune.stream/yt/${video_id}.mp4"
    
    # Try direct download
    if yt-dlp --no-warnings --no-playlist \
              --no-check-certificate \
              --socket-timeout 15 \
              --output "$output_file" \
              "$hobune_url" 2>/dev/null; then
        echo -e "${GREEN}     ✓ Downloaded from Hobune.stream${NC}"
        return 0
    fi
    
    echo -e "${RED}     ✗ Not found on Hobune.stream${NC}"
    return 1
}

# Master archive search function - tries all sources in order
search_archive() {
    local video_id="$1"
    
    echo -e "${BLUE}  → Searching archives...${NC}"
    
    mkdir -p "$ARCHIVE_DIR"
    
    # Try 1: GhostArchive
    if search_ghostarchive "$video_id"; then
        return 0
    fi
    
    # Try 2: Archive.org
    if search_archive_org "$video_id"; then
        return 0
    fi
    
    # Try 3: Wayback Machine (FIXED - multi-variant CDX query)
    if search_wayback "$video_id"; then
        return 0
    fi
    
    # Try 4: Hobune.stream
    if search_hobune "$video_id"; then
        return 0
    fi
    
    echo -e "${RED}     ✗ Not found in any archive${NC}"
    return 1
}

# ============================================================================
# ========== MAIN RETRY LOOP =================================================
# ============================================================================

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Retry Failed Downloads${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "TakData directory: $TAK_DATA_PATH"
echo "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
echo "Quality: $QUALITY"
echo "Browser: $BROWSER"
echo "Delay between retries: ${SLEEP_INTERVAL}s"
echo ""

if [ ! -f "$FAILED_LOG" ] || [ ! -s "$FAILED_LOG" ]; then
    echo -e "${YELLOW}No failed_ids.txt found or it's empty. Nothing to retry.${NC}"
    exit 1
fi

if ! check_internet; then
    wait_for_internet
fi

# Filter out permanently failed videos and already downloaded
TEMP_RETRY_LIST=".retry_list_temp.txt"
> "$TEMP_RETRY_LIST"

while IFS= read -r video_id; do
    [ -z "$video_id" ] && continue
    
    if grep -Fxq -- "$video_id" "$PERMANENTLY_FAILED_LOG" 2>/dev/null; then
        echo -e "${CYAN}  Skipping permanently failed: $video_id${NC}"
        remove_from_failed "$video_id"
    elif grep -Fxq -- "$video_id" "$DOWNLOADED_LOG" 2>/dev/null; then
        echo -e "${CYAN}  Skipping already downloaded: $video_id${NC}"
        remove_from_failed "$video_id"
    elif grep -Fxq -- "$video_id" "$RECOVERED_LOG" 2>/dev/null; then
        echo -e "${CYAN}  Skipping already recovered: $video_id${NC}"
        remove_from_failed "$video_id"
    else
        echo "$video_id" >> "$TEMP_RETRY_LIST"
    fi
done < "$FAILED_LOG"

TOTAL=$(wc -l < "$TEMP_RETRY_LIST")

if [ $TOTAL -eq 0 ]; then
    echo -e "${GREEN}All failed videos have been recovered or marked permanently failed!${NC}"
    rm -f "$TEMP_RETRY_LIST"
    exit 0
fi

echo -e "${CYAN}Videos to retry: $TOTAL${NC}"
echo ""

CURRENT=0
SUCCESS=0
RECOVERED=0
STILL_FAILED=0

while IFS= read -r video_id; do
    [ -z "$video_id" ] && continue
    
    CURRENT=$((CURRENT + 1))
    echo ""
    echo -e "${YELLOW}[$CURRENT/$TOTAL] RETRYING: $video_id${NC}"
    
    if ! check_internet; then
        wait_for_internet
    fi
    
    echo -e "${BLUE}  → Trying YouTube...${NC}"
    
    # ---- Robust YouTube download with multiple fallback methods ----
    download_success=0
    
    # Method 1: Standard with cookies (if browser specified)
    if [ "$BROWSER" != "none" ]; then
        yt-dlp --cookies-from-browser "$BROWSER" \
               --extractor-args youtubetab:skip=authcheck \
               $YTDLP_EXTRA_ARGS \
               --embed-thumbnail --add-metadata \
               --output "$OUTPUT_TEMPLATE" \
               --no-overwrites --continue \
               --no-check-certificate \
               "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1 && download_success=1
    fi
    
    # Method 2: Without cookies but with user agent
    if [ $download_success -eq 0 ]; then
        yt-dlp --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
               --extractor-args youtubetab:skip=authcheck \
               $YTDLP_EXTRA_ARGS \
               --embed-thumbnail --add-metadata \
               --output "$OUTPUT_TEMPLATE" \
               --no-overwrites --continue \
               "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1 && download_success=1
    fi
    
    # Method 3: Geo-bypass
    if [ $download_success -eq 0 ]; then
        yt-dlp --geo-bypass \
               --extractor-args youtubetab:skip=authcheck \
               $YTDLP_EXTRA_ARGS \
               --embed-thumbnail --add-metadata \
               --output "$OUTPUT_TEMPLATE" \
               --no-overwrites --continue \
               "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1 && download_success=1
    fi
    
    # Method 4: Android client (bypasses some restrictions)
    if [ $download_success -eq 0 ]; then
        yt-dlp --extractor-args "youtube:player_client=android" \
               $YTDLP_EXTRA_ARGS \
               --embed-thumbnail --add-metadata \
               --output "$OUTPUT_TEMPLATE" \
               --no-overwrites --continue \
               "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1 && download_success=1
    fi
    
    if [ $download_success -eq 1 ]; then
        echo -e "${GREEN}  ✓ Downloaded successfully${NC}"
        mark_downloaded "$video_id"
        remove_from_failed "$video_id"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${RED}  ✗ Still unavailable on YouTube${NC}"
        
        echo -e "${BLUE}  → Attempting archive recovery...${NC}"
        if search_archive "$video_id"; then
            echo -e "${GREEN}  ✓ Recovered from archive!${NC}"
            mark_recovered "$video_id"
            remove_from_failed "$video_id"
            RECOVERED=$((RECOVERED + 1))
        else
            echo -e "${RED}  ✗ Not found in any archive${NC}"
            echo -e "${YELLOW}  → Marked as permanently failed${NC}"
            mark_permanently_failed "$video_id"
            remove_from_failed "$video_id"
            STILL_FAILED=$((STILL_FAILED + 1))
        fi
    fi
    
    if [ $CURRENT -lt $TOTAL ]; then
        echo -e "${BLUE}  Waiting ${SLEEP_INTERVAL}s...${NC}"
        sleep "$SLEEP_INTERVAL"
    fi
done < "$TEMP_RETRY_LIST"

rm -f "$TEMP_RETRY_LIST"

# Ask to run Move-Recovered if files were recovered
if [ -d "$ARCHIVE_DIR" ] && [ -n "$(ls -A "$ARCHIVE_DIR" 2>/dev/null)" ]; then
    echo ""
    echo -e "${MAGENTA}Archive recovered files found in: $ARCHIVE_DIR${NC}"
    read -p "Run Move-Recovered.sh to process these files? (y/N): " -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        if [ -f "./Move-Recovered.sh" ]; then
            ./Move-Recovered.sh -o "$OUTPUT_DIR" -f "$FORMAT" -q "$QUALITY"
        else
            echo -e "${RED}Move-Recovered.sh not found${NC}"
        fi
    fi
fi

# Summary
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}RETRY COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ Downloaded from YouTube: $SUCCESS${NC}"
echo -e "${GREEN}✓ Recovered from archives: $RECOVERED${NC}"
echo -e "${RED}✗ Permanently failed: $STILL_FAILED${NC}"
echo ""
echo "Files saved to: $OUTPUT_DIR"
echo "Settings and logs saved to: $TAK_DATA_PATH"
echo ""
echo "Permanently failed videos saved to: $PERMANENTLY_FAILED_LOG"