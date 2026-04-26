#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
SLEEP_INTERVAL=11     # Default 11 seconds
FORMAT="mp3"          # Default format
QUALITY="mid"         # Default quality
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

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
    echo "Usage: $0 [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-q QUALITY] [-h]"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -t SECONDS    Sleep interval between retries (default: 11)"
    echo "  -f FORMAT     Output format (default: mp3)"
    echo "  -q QUALITY    Quality: low, mid, high (default: mid)"
    echo "  -h            Show this help message"
}

# Parse arguments
while getopts "o:t:f:q:h" opt; do
    case $opt in
        o) OUTPUT_DIR="$OPTARG" ;;
        t) SLEEP_INTERVAL="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        q) QUALITY="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

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

# ========== CHANGE TO OUTPUT DIRECTORY ==========
cd "$OUTPUT_DIR" || exit 1

# Set up hidden file paths with dot prefix
ARCHIVE_DIR=".archive_recovered"
RECOVERED_LOG=".recovered_ids.txt"
DOWNLOADED_LOG=".downloaded_ids.txt"
FAILED_LOG=".failed_ids.txt"
PERMANENTLY_FAILED_LOG=".permanently_failed_ids.txt"
YTDLP_ARCHIVE=".ytdlp_archive.txt"

mkdir -p "$ARCHIVE_DIR"
touch "$RECOVERED_LOG" "$DOWNLOADED_LOG" "$PERMANENTLY_FAILED_LOG" "$YTDLP_ARCHIVE"

# Functions
mark_recovered() { 
    echo "$1" >> "$RECOVERED_LOG"
    sync
}
mark_downloaded() { 
    echo "$1" >> "$DOWNLOADED_LOG"
    echo "youtube $1" >> "$YTDLP_ARCHIVE"
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

# Archive search function
search_archive() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}  → Searching archives...${NC}"
    
    mkdir -p "$ARCHIVE_DIR"
    
    # GhostArchive
    local ghost_url="https://ghostarchive.org/varchive/youtube/$video_id"
    local ghost_status=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 15 "$ghost_url" 2>/dev/null)
    
    if [ "$ghost_status" = "200" ]; then
        echo -e "${GREEN}     ✓ Found on GhostArchive, downloading...${NC}"
        yt-dlp --no-warnings --no-playlist --output "$output_file" "$ghost_url" 2>/dev/null && return 0
    fi
    
    # Archive.org
    local archive_url="https://archive.org/details/youtube-$video_id"
    local archive_status=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 15 "$archive_url" 2>/dev/null)
    
    if [ "$archive_status" = "200" ]; then
        echo -e "${GREEN}     ✓ Found on Archive.org, downloading...${NC}"
        yt-dlp --no-warnings --no-playlist -f "bestvideo+bestaudio/best" --output "$output_file" "$archive_url" 2>/dev/null && return 0
    fi
    
    # Wayback Machine
    local wayback_api="https://archive.org/wayback/available?url=https://youtube.com/watch?v=$video_id"
    local wayback_response=$(curl -sL --max-time 15 "$wayback_api" 2>/dev/null)
    
    if [ -n "$wayback_response" ]; then
        local wayback_timestamp=$(echo "$wayback_response" | sed -n 's/.*"timestamp":"\([0-9]*\)".*/\1/p' | head -1)
        
        if [ -n "$wayback_timestamp" ] && [ "$wayback_timestamp" != "null" ]; then
            local embed_url="https://web.archive.org/web/${wayback_timestamp}if_/https://www.youtube.com/embed/$video_id"
            echo -e "${GREEN}     ✓ Found Wayback capture, attempting download...${NC}"
            yt-dlp --no-warnings --no-playlist --output "$output_file" "$embed_url" 2>/dev/null && return 0
        fi
    fi
    
    # Hobune.stream
    local hobune_url="https://hobune.stream/yt/${video_id}.mp4"
    local hobune_status=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 10 "$hobune_url" 2>/dev/null)
    
    if [ "$hobune_status" = "200" ]; then
        echo -e "${GREEN}     ✓ Found on Hobune.stream, downloading...${NC}"
        yt-dlp --no-warnings --no-playlist --output "$output_file" "$hobune_url" 2>/dev/null && return 0
    fi
    
    echo -e "${RED}     ✗ Not found in any archive${NC}"
    return 1
}

# Main retry loop
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Retry Failed Downloads${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
echo "Quality: $QUALITY"
echo "Delay between retries: ${SLEEP_INTERVAL}s"
echo ""

if [ ! -f "$FAILED_LOG" ] || [ ! -s "$FAILED_LOG" ]; then
    echo -e "${YELLOW}No .failed_ids.txt found or it's empty. Nothing to retry.${NC}"
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
    
    # Use -- with grep to handle hyphens
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
    yt-dlp --cookies-from-browser firefox \
           --extractor-args youtubetab:skip=authcheck \
           --download-archive "$YTDLP_ARCHIVE" \
           $YTDLP_EXTRA_ARGS \
           --embed-thumbnail --add-metadata \
           --output "$OUTPUT_TEMPLATE" \
           --no-overwrites --continue \
           "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
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
echo "Permanently failed videos saved to: $PERMANENTLY_FAILED_LOG"
