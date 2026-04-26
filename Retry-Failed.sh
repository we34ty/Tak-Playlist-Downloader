#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
SLEEP_INTERVAL=11     # Default 11 seconds
FORMAT="mp3"          # Default format
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

# Help function
show_help() {
    echo "Usage: $0 [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-h]"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -t SECONDS    Sleep interval between retries (default: 11)"
    echo "  -f FORMAT     Output format (default: mp3)"
    echo "  -h            Show this help message"
    echo ""
    echo "Note: Permanently failed videos will be skipped automatically"
}

# Parse arguments
while getopts "o:t:f:h" opt; do
    case $opt in
        o) OUTPUT_DIR="$OPTARG" ;;
        t) SLEEP_INTERVAL="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

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
    YTDLP_FORMAT_ARGS="-f ba -x --audio-format $FORMAT_LOWER"
    OUTPUT_TEMPLATE="%(uploader)s - %(title)s.%(ext)s"
    echo -e "${BLUE}Format: $FORMAT_LOWER (audio only)${NC}"
elif echo "$VIDEO_FORMATS" | grep -qw "$FORMAT_LOWER"; then
    DOWNLOAD_TYPE="video"
    YTDLP_FORMAT_ARGS="-f bestvideo+bestaudio --merge-output-format ${FORMAT_LOWER}"
    OUTPUT_TEMPLATE="%(uploader)s - %(title)s.%(ext)s"
    echo -e "${BLUE}Format: $FORMAT_LOWER (video + audio)${NC}"
else
    echo -e "${RED}ERROR: Unsupported format '$FORMAT'${NC}"
    exit 1
fi

# ========== CHANGE TO OUTPUT DIRECTORY ==========
cd "$OUTPUT_DIR" || exit 1

# Set up file paths
ARCHIVE_DIR="archive_recovered"
RECOVERED_LOG="recovered_ids.txt"
DOWNLOADED_LOG="downloaded_ids.txt"
FAILED_LOG="failed_ids.txt"
PERMANENTLY_FAILED_LOG="permanently_failed_ids.txt"

mkdir -p "$ARCHIVE_DIR"
touch "$RECOVERED_LOG" "$DOWNLOADED_LOG" "$PERMANENTLY_FAILED_LOG"

# Functions
is_recovered() { grep -Fxq "$1" "$RECOVERED_LOG" 2>/dev/null; }
is_downloaded() { grep -Fxq "$1" "$DOWNLOADED_LOG" 2>/dev/null; }
is_permanently_failed() { grep -Fxq "$1" "$PERMANENTLY_FAILED_LOG" 2>/dev/null; }

mark_recovered() { echo "$1" >> "$RECOVERED_LOG"; }
mark_downloaded() { echo "$1" >> "$DOWNLOADED_LOG"; }
mark_permanently_failed() { echo "$1" >> "$PERMANENTLY_FAILED_LOG"; }

remove_from_failed() {
    local video_id="$1"
    grep -Fxv "$video_id" "$FAILED_LOG" > "$FAILED_LOG.tmp" 2>/dev/null
    mv "$FAILED_LOG.tmp" "$FAILED_LOG" 2>/dev/null
}

# Archive search function
search_archive() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}  → Searching archives...${NC}"
    
    mkdir -p "$ARCHIVE_DIR"
    
    local ghost_url="https://ghostarchive.org/varchive/youtube/$video_id"
    if curl -s -o /dev/null -w "%{http_code}" "$ghost_url" 2>/dev/null | grep -q "200"; then
        yt-dlp --no-warnings --no-playlist --output "$output_file" "$ghost_url" 2>/dev/null && return 0
    fi
    
    local archive_url="https://archive.org/details/youtube-$video_id"
    if curl -s -o /dev/null -w "%{http_code}" "$archive_url" 2>/dev/null | grep -q "200"; then
        yt-dlp --no-warnings --no-playlist -f "bestvideo+bestaudio/best" --output "$output_file" "$archive_url" 2>/dev/null && return 0
    fi
    
    local wayback_timestamp=$(curl -s "https://archive.org/wayback/available?url=https://youtube.com/watch?v=$video_id" 2>/dev/null | grep -oP '"timestamp":"\K[0-9]+' | head -1)
    if [ -n "$wayback_timestamp" ]; then
        local embed_url="https://web.archive.org/web/${wayback_timestamp}if_/https://www.youtube.com/embed/$video_id"
        yt-dlp --no-warnings --no-playlist --output "$output_file" "$embed_url" 2>/dev/null && return 0
    fi
    
    return 1
}

# Main retry loop
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Retry Failed Downloads${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
echo "Delay between retries: ${SLEEP_INTERVAL}s"
echo ""

if [ ! -f "$FAILED_LOG" ] || [ ! -s "$FAILED_LOG" ]; then
    echo -e "${YELLOW}No failed_ids.txt found or it's empty. Nothing to retry.${NC}"
    exit 1
fi

# Check internet
if ! check_internet; then
    wait_for_internet
fi

# Filter out permanently failed videos
TEMP_RETRY_LIST=".retry_list_temp.txt"
> "$TEMP_RETRY_LIST"

while IFS= read -r video_id; do
    [ -z "$video_id" ] && continue
    if is_permanently_failed "$video_id"; then
        echo -e "${CYAN}  Skipping permanently failed: $video_id${NC}"
        remove_from_failed "$video_id"
    elif ! is_recovered "$video_id" && ! is_downloaded "$video_id"; then
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
    
    # Check internet before each attempt
    if ! check_internet; then
        wait_for_internet
    fi
    
    # Try YouTube
    echo -e "${BLUE}  → Trying YouTube...${NC}"
    if yt-dlp --cookies-from-browser firefox \
           --extractor-args youtubetab:skip=authcheck \
           $YTDLP_FORMAT_ARGS \
           --embed-thumbnail --add-metadata \
           --output "$OUTPUT_TEMPLATE" \
           --no-overwrites --continue --no-warnings \
           "https://youtube.com/watch?v=$video_id" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Downloaded successfully${NC}"
        mark_downloaded "$video_id"
        remove_from_failed "$video_id"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${RED}  ✗ Still unavailable on YouTube${NC}"
        
        # Try archive recovery
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
    
    # Delay
    if [ $CURRENT -lt $TOTAL ]; then
        echo -e "${BLUE}  Waiting ${SLEEP_INTERVAL}s...${NC}"
        sleep "$SLEEP_INTERVAL"
    fi
done < "$TEMP_RETRY_LIST"

rm -f "$TEMP_RETRY_LIST"

# Process archive_recovered files
if [ -d "$ARCHIVE_DIR" ] && [ -n "$(ls -A "$ARCHIVE_DIR" 2>/dev/null)" ]; then
    echo ""
    echo -e "${BLUE}Processing recovered files...${NC}"
    for file in "$ARCHIVE_DIR"/*; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        if [[ "${filename##*.}" == "$FORMAT_LOWER" ]]; then
            mv "$file" "$OUTPUT_DIR/" 2>/dev/null
            echo -e "${GREEN}  ✓ Moved: $filename${NC}"
        else
            ffmpeg -i "$file" -vn -ar 44100 -ac 2 -b:a 192k "$OUTPUT_DIR/${filename%.*}.$FORMAT_LOWER" -y 2>/dev/null
            if [ $? -eq 0 ]; then
                rm "$file"
                echo -e "${GREEN}  ✓ Converted: ${filename%.*}.$FORMAT_LOWER${NC}"
            fi
        fi
    done
    rmdir "$ARCHIVE_DIR" 2>/dev/null
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
echo "These videos will not be retried again."
