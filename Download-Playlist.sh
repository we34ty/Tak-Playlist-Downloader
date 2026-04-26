#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
SLEEP_INTERVAL=11     # Default 11 seconds
ENABLE_ARCHIVE=false  # Default false (disabled)
PLAYLIST_URL=""       # Required argument
FORMAT="mp3"          # Default format
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Clean playlist URL
clean_playlist_url() {
    echo "$1" | sed 's/&si=[^&]*//g' | sed 's/?si=[^&]*//g'
}

# Internet connection check
check_internet() {
    # Try to reach multiple reliable hosts
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || \
       ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || \
       curl -s --max-time 3 https://www.google.com >/dev/null 2>&1; then
        return 0  # Internet is available
    else
        return 1  # No internet connection
    fi
}

# Wait for internet to return
wait_for_internet() {
    local wait_time=30
    local max_wait=3600  # Maximum 1 hour
    local elapsed=0
    
    echo -e "${YELLOW}⚠️  No internet connection detected${NC}"
    echo -e "${YELLOW}Waiting for connection to resume...${NC}"
    
    while ! check_internet; do
        sleep "$wait_time"
        elapsed=$((elapsed + wait_time))
        if [ $elapsed -ge $max_wait ]; then
            echo -e "${RED}No internet connection after 1 hour. Exiting.${NC}"
            exit 1
        fi
        echo -e "${BLUE}  Still waiting... (${elapsed}s elapsed)${NC}"
    done
    
    echo -e "${GREEN}✓ Internet connection restored! Resuming downloads.${NC}"
    sleep 5
}

# Help function
show_help() {
    echo "Usage: $0 -p PLAYLIST_URL [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-a] [-h]"
    echo ""
    echo "Required:"
    echo "  -p URL        YouTube playlist URL"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -t SECONDS    Sleep between downloads (default: 11, 0 = no delay)"
    echo "  -f FORMAT     Output format: mp3, m4a, opus, flac, mp4, webm, etc."
    echo "  -a            Enable archive recovery for deleted videos"
    echo "  -h            Show this help"
}

# Parse arguments
while getopts "p:o:t:f:ah" opt; do
    case $opt in
        p) PLAYLIST_URL="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) SLEEP_INTERVAL="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        a) ENABLE_ARCHIVE=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Check required argument
if [ -z "$PLAYLIST_URL" ]; then
    echo -e "${RED}ERROR: Playlist URL is required${NC}"
    show_help
    exit 1
fi

# Clean URL
PLAYLIST_URL=$(clean_playlist_url "$PLAYLIST_URL")

# Validate sleep interval
if ! [[ "$SLEEP_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Sleep interval must be a number${NC}"
    exit 1
fi

# Set format parameters
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

# ========== CREATE OUTPUT DIRECTORY ==========
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR" || exit 1

# Set up log files
LOG_FILE="downloaded_ids.txt"
FAILED_LOG="failed_ids.txt"
RECOVERED_LOG="recovered_ids.txt"
PERMANENTLY_FAILED_LOG="permanently_failed_ids.txt"  # NEW: Track permanently failed videos
ARCHIVE_DIR="archive_recovered"
VIDEO_IDS_FILE="playlist_videos.txt"

# Initialize files
touch "$LOG_FILE" "$FAILED_LOG" "$RECOVERED_LOG" "$PERMANENTLY_FAILED_LOG"

# Functions
is_downloaded() {
    grep -Fxq "$1" "$LOG_FILE" 2>/dev/null || grep -Fxq "$1" "$RECOVERED_LOG" 2>/dev/null
}

is_permanently_failed() {
    grep -Fxq "$1" "$PERMANENTLY_FAILED_LOG" 2>/dev/null
}

mark_downloaded() { echo "$1" >> "$LOG_FILE"; }
mark_recovered() { echo "$1" >> "$RECOVERED_LOG"; }
mark_failed() { echo "$1" >> "$FAILED_LOG"; }
mark_permanently_failed() { echo "$1" >> "$PERMANENTLY_FAILED_LOG"; }

cleanup() {
    echo -e "\n\n${YELLOW}Interrupted. Progress saved. Run again to resume.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Archive search function (fixed to download only best format)
search_archive() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}  → Searching archives...${NC}"
    
    mkdir -p "$ARCHIVE_DIR"
    
    # METHOD 1: GhostArchive
    local ghost_url="https://ghostarchive.org/varchive/youtube/$video_id"
    if curl -s -o /dev/null -w "%{http_code}" "$ghost_url" 2>/dev/null | grep -q "200"; then
        yt-dlp --no-warnings --no-playlist --output "$output_file" "$ghost_url" 2>/dev/null && return 0
    fi
    
    # METHOD 2: Archive.org - best format only
    local archive_url="https://archive.org/details/youtube-$video_id"
    if curl -s -o /dev/null -w "%{http_code}" "$archive_url" 2>/dev/null | grep -q "200"; then
        yt-dlp --no-warnings --no-playlist -f "bestvideo+bestaudio/best" --output "$output_file" "$archive_url" 2>/dev/null && return 0
    fi
    
    # METHOD 3: Wayback Machine
    local wayback_timestamp=$(curl -s "https://archive.org/wayback/available?url=https://youtube.com/watch?v=$video_id" 2>/dev/null | grep -oP '"timestamp":"\K[0-9]+' | head -1)
    if [ -n "$wayback_timestamp" ]; then
        local embed_url="https://web.archive.org/web/${wayback_timestamp}if_/https://www.youtube.com/embed/$video_id"
        yt-dlp --no-warnings --no-playlist --output "$output_file" "$embed_url" 2>/dev/null && return 0
    fi
    
    # METHOD 4: Hobune.stream
    local hobune_url="https://hobune.stream/yt/${video_id}.mp4"
    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$hobune_url" 2>/dev/null | grep -q "200"; then
        yt-dlp --no-warnings --no-playlist --output "$output_file" "$hobune_url" 2>/dev/null && return 0
    fi
    
    return 1
}

# ========== EXTRACT VIDEO IDs ==========
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Tak Playlist Downloader${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
echo "Delay: ${SLEEP_INTERVAL}s"
echo "Archive recovery: $( [ "$ENABLE_ARCHIVE" = true ] && echo "ON" || echo "OFF" )"
echo ""

# Check internet before starting
if ! check_internet; then
    wait_for_internet
fi

echo -e "${BLUE}Fetching playlist...${NC}"

# Clear and extract IDs
> "$VIDEO_IDS_FILE"

# Direct extraction
yt-dlp --cookies-from-browser firefox \
       --flat-playlist \
       --print "%(id)s" \
       "$PLAYLIST_URL" >> "$VIDEO_IDS_FILE" 2>/dev/null

if [ ! -s "$VIDEO_IDS_FILE" ]; then
    yt-dlp --cookies-from-browser firefox \
           --extractor-args youtubetab:skip=authcheck \
           --flat-playlist --print "%(id)s" \
           "$PLAYLIST_URL" >> "$VIDEO_IDS_FILE" 2>/dev/null
fi

sed -i '/^$/d' "$VIDEO_IDS_FILE" 2>/dev/null

if [ ! -s "$VIDEO_IDS_FILE" ]; then
    echo -e "${RED}ERROR: Could not extract video IDs${NC}"
    exit 1
fi

TOTAL=$(wc -l < "$VIDEO_IDS_FILE")
DOWNLOADED_COUNT=$(grep -Fxf "$VIDEO_IDS_FILE" "$LOG_FILE" 2>/dev/null | wc -l)
RECOVERED_COUNT=$(grep -Fxf "$VIDEO_IDS_FILE" "$RECOVERED_LOG" 2>/dev/null | wc -l)
PERMANENTLY_FAILED_COUNT=$(grep -Fxf "$VIDEO_IDS_FILE" "$PERMANENTLY_FAILED_LOG" 2>/dev/null | wc -l)
REMAINING=$((TOTAL - DOWNLOADED_COUNT - RECOVERED_COUNT - PERMANENTLY_FAILED_COUNT))

echo "Total videos: $TOTAL"
echo "Already downloaded: $DOWNLOADED_COUNT"
echo "Recovered from archives: $RECOVERED_COUNT"
echo "Permanently failed (skipped): $PERMANENTLY_FAILED_COUNT"
echo "Remaining: $REMAINING"
echo ""

# ========== DOWNLOAD LOOP ==========
PROCESSED=0
YOUTUBE_SUCCESS=0
RECOVERED_VIDEOS=0
FAILED_VIDEOS=0
SKIPPED_PERMANENT=0

while IFS= read -r video_id; do
    [ -z "$video_id" ] && continue
    
    # Skip permanently failed videos (they won't be checked again)
    if is_permanently_failed "$video_id"; then
        echo "[$(printf "%4d" $((++PROCESSED)))/$TOTAL] SKIP: $video_id (permanently unavailable)"
        SKIPPED_PERMANENT=$((SKIPPED_PERMANENT + 1))
        continue
    fi
    
    # Skip already downloaded or recovered
    if is_downloaded "$video_id"; then
        echo "[$(printf "%4d" $((++PROCESSED)))/$TOTAL] SKIP: $video_id (already have)"
        continue
    fi
    
    PROCESSED=$((PROCESSED + 1))
    echo ""
    echo -e "${YELLOW}[$PROCESSED/$TOTAL] DOWNLOADING: $video_id${NC}"
    
    # Check internet before each download attempt
    if ! check_internet; then
        wait_for_internet
    fi
    
    # Download from YouTube
    if yt-dlp --cookies-from-browser firefox \
           --extractor-args youtubetab:skip=authcheck \
           $YTDLP_FORMAT_ARGS \
           --embed-thumbnail --add-metadata \
           --output "$OUTPUT_TEMPLATE" \
           --no-overwrites --continue --no-warnings \
           "https://youtube.com/watch?v=$video_id" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Success${NC}"
        mark_downloaded "$video_id"
        YOUTUBE_SUCCESS=$((YOUTUBE_SUCCESS + 1))
    else
        echo -e "${RED}  ✗ YouTube failed${NC}"
        
        if [ "$ENABLE_ARCHIVE" = true ]; then
            if search_archive "$video_id"; then
                echo -e "${GREEN}  ✓ Recovered from archive${NC}"
                mark_recovered "$video_id"
                RECOVERED_VIDEOS=$((RECOVERED_VIDEOS + 1))
            else
                echo -e "${RED}  ✗ Not found in any archive${NC}"
                echo -e "${YELLOW}  → Marked as permanently failed (will not retry)${NC}"
                mark_permanently_failed "$video_id"
                FAILED_VIDEOS=$((FAILED_VIDEOS + 1))
            fi
        else
            echo -e "${YELLOW}  → Archive recovery disabled. Use -a to enable archive search.${NC}"
            mark_failed "$video_id"
            FAILED_VIDEOS=$((FAILED_VIDEOS + 1))
        fi
    fi
    
    # Delay
    if [ $SLEEP_INTERVAL -gt 0 ] && [ $PROCESSED -lt $TOTAL ]; then
        echo -e "${BLUE}  Waiting ${SLEEP_INTERVAL}s...${NC}"
        sleep "$SLEEP_INTERVAL"
    fi
done < "$VIDEO_IDS_FILE"

# Process recovered files
if [ "$ENABLE_ARCHIVE" = true ] && [ -d "$ARCHIVE_DIR" ]; then
    echo ""
    echo -e "${BLUE}Processing recovered files...${NC}"
    for file in "$ARCHIVE_DIR"/*; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        
        # Skip duplicate resolution files
        base_name=$(echo "$filename" | sed 's/ [0-9]*x[0-9]*\.mp4//' | sed 's/\.[^.]*$//')
        
        if [[ "${filename##*.}" == "$FORMAT_LOWER" ]]; then
            mv "$file" "$OUTPUT_DIR/" 2>/dev/null
            echo -e "${GREEN}  ✓ Moved: $filename${NC}"
        else
            # For non-MP4 files, keep as-is or convert
            ffmpeg -i "$file" -vn -ar 44100 -ac 2 -b:a 192k "$OUTPUT_DIR/${filename%.*}.$FORMAT_LOWER" -y 2>/dev/null
            if [ $? -eq 0 ]; then
                rm "$file"
                echo -e "${GREEN}  ✓ Converted: ${filename%.*}.$FORMAT_LOWER${NC}"
            fi
        fi
    done
    
    # Clean up empty archive directory
    rmdir "$ARCHIVE_DIR" 2>/dev/null
fi

# Summary
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}COMPLETE!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ YouTube downloads: $YOUTUBE_SUCCESS${NC}"
echo -e "${GREEN}✓ Archive recovered: $RECOVERED_VIDEOS${NC}"
echo -e "${RED}✗ Permanently failed: $FAILED_VIDEOS${NC}"
echo -e "${BLUE}○ Skipped (permanently failed from previous runs): $SKIPPED_PERMANENT${NC}"
echo ""
echo "Files saved to: $OUTPUT_DIR"
echo ""
echo "Note: Permanently failed videos saved to: $PERMANENTLY_FAILED_LOG"
echo "These videos will NOT be retried in future runs."
