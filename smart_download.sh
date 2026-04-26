#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
SLEEP_INTERVAL=11     # Default 11 seconds
ENABLE_ARCHIVE=false  # Default false (disabled)
PLAYLIST_URL=""       # Required argument
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Help function
show_help() {
    echo "Usage: $0 -p PLAYLIST_URL [-o OUTPUT_DIR] [-t SLEEP_INTERVAL] [-a] [-h]"
    echo ""
    echo "Required:"
    echo "  -p URL        YouTube playlist URL"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -t SECONDS    Sleep interval between downloads (default: 11)"
    echo "  -a            Enable archive recovery (default: disabled)"
    echo "  -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -p \"https://youtube.com/playlist?list=ABC123\""
    echo "  $0 -p \"URL\" -o \"$HOME/Music\" -t 5 -a"
    echo "  $0 -p \"URL\" -o \"\$(pwd)/playlist\" -t 15"
}

# Parse arguments
while getopts "p:o:t:ah" opt; do
    case $opt in
        p) PLAYLIST_URL="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) SLEEP_INTERVAL="$OPTARG" ;;
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

# Validate sleep interval is a number
if ! [[ "$SLEEP_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Sleep interval must be a number${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Set up log files
LOG_FILE="$OUTPUT_DIR/downloaded_ids.txt"
FAILED_LOG="$OUTPUT_DIR/failed_ids.txt"
RECOVERED_LOG="$OUTPUT_DIR/recovered_ids.txt"
ARCHIVE_DIR="$OUTPUT_DIR/archive_recovered"

touch "$LOG_FILE" "$FAILED_LOG" "$RECOVERED_LOG"
cd "$OUTPUT_DIR" || exit 1

# Functions
is_downloaded() {
    grep -Fxq "$1" "$LOG_FILE" 2>/dev/null || grep -Fxq "$1" "$RECOVERED_LOG" 2>/dev/null
}

mark_downloaded() {
    echo "$1" >> "$LOG_FILE"
}

mark_recovered() {
    echo "$1" >> "$RECOVERED_LOG"
}

mark_failed() {
    echo "$1" >> "$FAILED_LOG"
}

cleanup() {
    echo -e "\n\n${YELLOW}Interrupted. Progress saved. Run again to resume.${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Enhanced archive search function (only used if -a is enabled)
search_archive() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}  → Searching archives for $video_id...${NC}"
    
    # METHOD 1: GhostArchive
    local ghost_url="https://ghostarchive.org/varchive/youtube/$video_id"
    local ghost_check=$(curl -s -o /dev/null -w "%{http_code}" "$ghost_url" 2>/dev/null)
    
    if [ "$ghost_check" = "200" ]; then
        echo -e "${BLUE}  → Found on GhostArchive, attempting download...${NC}"
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$ghost_url" 2>/dev/null && return 0
    fi
    
    # METHOD 2: Wayback Machine
    echo -e "${BLUE}  → Checking Wayback Machine...${NC}"
    local wayback_api="https://archive.org/wayback/available?url=https://youtube.com/watch?v=$video_id"
    local wayback_timestamp=$(curl -s "$wayback_api" | grep -oP '"timestamp":"\K[0-9]+' | head -1)
    
    if [ -n "$wayback_timestamp" ]; then
        local embed_url="https://web.archive.org/web/${wayback_timestamp}if_/https://www.youtube.com/embed/$video_id"
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$embed_url" 2>/dev/null && return 0
    fi
    
    # METHOD 3: Hobune.stream
    local hobune_url="https://hobune.stream/yt/${video_id}.mp4"
    local hobune_check=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$hobune_url" 2>/dev/null)
    
    if [ "$hobune_check" = "200" ]; then
        echo -e "${BLUE}  → Found on Hobune.stream, downloading...${NC}"
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$hobune_url" 2>/dev/null && return 0
    fi
    
    return 1
}

# Extract video IDs from playlist
VIDEO_IDS_FILE="$OUTPUT_DIR/playlist_videos.txt"
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Smart YouTube Playlist Downloader${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "Delay between downloads: ${SLEEP_INTERVAL}s"
echo "Archive recovery: $( [ "$ENABLE_ARCHIVE" = true ] && echo "ENABLED" || echo "DISABLED" )"
echo ""

echo -e "${BLUE}Fetching playlist information...${NC}"

# Try multiple methods to get IDs
yt-dlp --cookies-from-browser firefox \
       --extractor-args youtubetab:skip=authcheck \
       --flat-playlist --print "%(id)s" \
       "$PLAYLIST_URL" 2>/dev/null > "$VIDEO_IDS_FILE"

if [ ! -s "$VIDEO_IDS_FILE" ]; then
    yt-dlp --cookies-from-browser firefox \
           --extractor-args "youtube:player_client=android" \
           --extractor-args youtubetab:skip=authcheck \
           --flat-playlist --print "%(id)s" \
           "$PLAYLIST_URL" 2>/dev/null > "$VIDEO_IDS_FILE"
fi

if [ ! -s "$VIDEO_IDS_FILE" ]; then
    echo -e "${RED}ERROR: Could not extract video IDs${NC}"
    exit 1
fi

TOTAL=$(wc -l < "$VIDEO_IDS_FILE")
DOWNLOADED_COUNT=$(grep -Fxcf "$VIDEO_IDS_FILE" "$LOG_FILE" 2>/dev/null || echo 0)
RECOVERED_COUNT=$(grep -Fxcf "$VIDEO_IDS_FILE" "$RECOVERED_LOG" 2>/dev/null || echo 0)
REMAINING=$((TOTAL - DOWNLOADED_COUNT - RECOVERED_COUNT))

echo "Total videos: $TOTAL"
echo "Successfully downloaded: $DOWNLOADED_COUNT"
echo "Recovered from archives: $RECOVERED_COUNT"
echo "Remaining: $REMAINING"
echo ""

# Download loop
PROCESSED=0
SKIPPED=0
FAILED_VIDEOS=0
RECOVERED_VIDEOS=0
YOUTUBE_SUCCESS=0

while IFS= read -r video_id; do
    # Check if already downloaded or recovered
    if is_downloaded "$video_id"; then
        echo "[$(printf "%4d" $((++PROCESSED)))/$TOTAL] SKIP: $video_id (already have)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    PROCESSED=$((PROCESSED + 1))
    echo ""
    echo -e "${YELLOW}[$(printf "%4d" $PROCESSED)/$TOTAL] PROCESSING: $video_id${NC}"
    
    # Try normal yt-dlp download first
    echo -e "${BLUE}  → Trying YouTube...${NC}"
    yt-dlp --cookies-from-browser firefox \
           --extractor-args youtubetab:skip=authcheck \
           -f "ba" -x --audio-format mp3 --audio-quality 0 \
           --embed-thumbnail --add-metadata \
           --output "%(uploader)s - %(title)s.%(ext)s" \
           --no-overwrites --continue --no-warnings \
           "https://youtube.com/watch?v=$video_id" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Downloaded successfully from YouTube${NC}"
        mark_downloaded "$video_id"
        YOUTUBE_SUCCESS=$((YOUTUBE_SUCCESS + 1))
    else
        echo -e "${RED}  ✗ Failed on YouTube (private/deleted/blocked/age-restricted)${NC}"
        
        # Try archive recovery only if enabled
        if [ "$ENABLE_ARCHIVE" = true ]; then
            echo -e "${BLUE}  → Attempting archive recovery...${NC}"
            if search_archive "$video_id"; then
                echo -e "${GREEN}  ✓ Recovered from archive!${NC}"
                mark_recovered "$video_id"
                RECOVERED_VIDEOS=$((RECOVERED_VIDEOS + 1))
            else
                echo -e "${RED}  ✗ Not found in any archive${NC}"
                mark_failed "$video_id"
                FAILED_VIDEOS=$((FAILED_VIDEOS + 1))
            fi
        else
            echo -e "${YELLOW}  → Archive recovery disabled (use -a to enable)${NC}"
            mark_failed "$video_id"
            FAILED_VIDEOS=$((FAILED_VIDEOS + 1))
        fi
    fi
    
    # Delay (skip after last)
    if [ $PROCESSED -lt $TOTAL ]; then
        echo -e "${BLUE}  Waiting ${SLEEP_INTERVAL}s...${NC}"
        sleep "$SLEEP_INTERVAL"
    fi
done < "$VIDEO_IDS_FILE"

# Process archive_recovered files if they exist
if [ "$ENABLE_ARCHIVE" = true ] && [ -d "$ARCHIVE_DIR" ] && [ -n "$(ls -A "$ARCHIVE_DIR" 2>/dev/null)" ]; then
    echo ""
    echo -e "${BLUE}Processing recovered files...${NC}"
    
    for file in "$ARCHIVE_DIR"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            extension="${filename##*.}"
            name_without_ext="${filename%.*}"
            
            if [[ "${extension,,}" == "mp3" ]]; then
                mv "$file" "$OUTPUT_DIR/" 2>/dev/null
                echo -e "${GREEN}  ✓ Moved: $filename${NC}"
            else
                temp_mp3="$OUTPUT_DIR/${name_without_ext}.mp3"
                ffmpeg -i "$file" -vn -ar 44100 -ac 2 -b:a 192k "$temp_mp3" -y 2>/dev/null
                if [ $? -eq 0 ]; then
                    rm "$file"
                    echo -e "${GREEN}  ✓ Converted: ${name_without_ext}.mp3${NC}"
                fi
            fi
        fi
    done
    
    rmdir "$ARCHIVE_DIR" 2>/dev/null
fi

# Final summary
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}DOWNLOAD COMPLETE!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Total videos in playlist: $TOTAL"
echo "Videos processed: $PROCESSED"
echo "Skipped (already had): $SKIPPED"
echo -e "${GREEN}✓ Downloaded from YouTube: $YOUTUBE_SUCCESS${NC}"
echo -e "${GREEN}✓ Recovered from archives: $RECOVERED_VIDEOS${NC}"
echo -e "${RED}✗ Failed (not found anywhere): $FAILED_VIDEOS${NC}"
echo ""
echo "Files saved to: $OUTPUT_DIR"
if [ "$ENABLE_ARCHIVE" = true ]; then
    echo "Download log: $LOG_FILE"
    echo "Recovered log: $RECOVERED_LOG"
    echo "Failed log: $FAILED_LOG"
fi
