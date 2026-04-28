#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
SLEEP_INTERVAL=11     # Default 11 seconds
ENABLE_ARCHIVE=false  # Default false (disabled)
PLAYLIST_URL=""       # Required argument
FORMAT="mp3"          # Default format
QUALITY="mid"         # Default quality (low/mid/high)
CONFIG_FILE=".download_config.txt"
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Function to load saved configuration
load_saved_config() {
    local config_path="$1"
    
    if [ -f "$config_path" ]; then
        echo -e "${BLUE}Loading saved configuration from: $config_path${NC}"
        # Source the config file (it's just KEY=VALUE format)
        source "$config_path"
        return 0
    fi
    return 1
}

# Function to save configuration
save_config() {
    local config_path="$1"
    local playlist_url="$2"
    local output_dir="$3"
    local sleep_interval="$4"
    local format="$5"
    local quality="$6"
    local enable_archive="$7"
    
    cat > "$config_path" << EOF
# Tak Playlist Downloader Configuration
# Generated on $(date '+%Y-%m-%d %H:%M:%S')
PLAYLIST_URL="$playlist_url"
OUTPUT_DIR="$output_dir"
SLEEP_INTERVAL=$sleep_interval
FORMAT="$format"
QUALITY="$quality"
ENABLE_ARCHIVE=$enable_archive
EOF
    echo -e "${BLUE}Configuration saved to: $config_path${NC}"
}

# Clean playlist URL
clean_playlist_url() {
    echo "$1" | sed 's/&si=[^&]*//g' | sed 's/?si=[^&]*//g'
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

# Wait for internet to return
wait_for_internet() {
    local wait_time=30
    local max_wait=3600
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

# Set quality parameters - ALWAYS convert to specified format
set_quality_params() {
    local quality="$1"
    local format="$2"
    local format_lower=$(echo "$format" | tr '[:upper:]' '[:lower:]')
    local audio_formats="mp3 m4a aac flac wav opus"
    local video_formats="mp4 webm mkv avi mov"
    
    if echo "$audio_formats" | grep -qw "$format_lower"; then
        case "$quality" in
            low)
                AUDIO_QUALITY="5"
                ;;
            mid)
                AUDIO_QUALITY="2"
                ;;
            high)
                AUDIO_QUALITY="0"
                ;;
            *)
                AUDIO_QUALITY="2"
                ;;
        esac
        YTDLP_EXTRA_ARGS="-f bestaudio -x --audio-format ${format_lower} --audio-quality ${AUDIO_QUALITY}"
        echo -e "${BLUE}Audio quality: $quality (${format_lower})${NC}"
        
    elif echo "$video_formats" | grep -qw "$format_lower"; then
        case "$quality" in
            low)
                YTDLP_EXTRA_ARGS="-f worstvideo+worstaudio --merge-output-format ${format_lower}"
                echo -e "${BLUE}Video quality: $quality (worst available)${NC}"
                ;;
            mid)
                YTDLP_EXTRA_ARGS="-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format ${format_lower}"
                echo -e "${BLUE}Video quality: $quality (up to 480p)${NC}"
                ;;
            high)
                YTDLP_EXTRA_ARGS="-f bestvideo+bestaudio --merge-output-format ${format_lower}"
                echo -e "${BLUE}Video quality: $quality (best available)${NC}"
                ;;
            *)
                YTDLP_EXTRA_ARGS="-f bestvideo+bestaudio --merge-output-format ${format_lower}"
                echo -e "${BLUE}Video quality: mid (up to 480p)${NC}"
                ;;
        esac
    fi
}

# Help function
show_help() {
    echo "Usage: $0 -p PLAYLIST_URL [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-q QUALITY] [-a] [-h]"
    echo ""
    echo "Required (first run only):"
    echo "  -p URL        YouTube playlist URL"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -t SECONDS    Sleep between downloads (default: 11, 0 = no delay)"
    echo "  -f FORMAT     Output format: mp3, m4a, opus, flac, mp4, webm, etc. (default: mp3)"
    echo "  -q QUALITY    Quality: low, mid, high (default: mid)"
    echo "                Audio: low(80k), mid(192k), high(320k)"
    echo "                Video: low(worst), mid(480p), high(best)"
    echo "  -a            Enable archive recovery for deleted videos (Linux only)"
    echo "  -h            Show this help"
    echo ""
    echo "Note: Settings are saved in .download_config.txt in the output directory."
    echo "      Subsequent runs without -p will use saved playlist URL."
}

# Parse arguments
while getopts "p:o:t:f:q:ah" opt; do
    case $opt in
        p) PLAYLIST_URL="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) SLEEP_INTERVAL="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        q) QUALITY="$OPTARG" ;;
        a) ENABLE_ARCHIVE=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Save original command line arguments to track what was explicitly provided
HAS_P=0
HAS_O=0
HAS_T=0
HAS_F=0
HAS_Q=0
HAS_A=0

# Re-parse to track which arguments were explicitly provided
for arg in "$@"; do
    case "$arg" in
        -p) HAS_P=1 ;;
        -o) HAS_O=1 ;;
        -t) HAS_T=1 ;;
        -f) HAS_F=1 ;;
        -q) HAS_Q=1 ;;
        -a) HAS_A=1 ;;
    esac
done

# ========== CHECK FOR SAVED CONFIGURATION IF NO -p PROVIDED ==========
if [ $HAS_P -eq 0 ]; then
    # Determine config file path
    CONFIG_PATH="$OUTPUT_DIR/$CONFIG_FILE"
    if [ -f "$CONFIG_PATH" ]; then
        # Load saved configuration
        source "$CONFIG_PATH"
        
        echo -e "${GREEN}[INFO] Found saved configuration from: $(grep '^#' "$CONFIG_PATH" | head -1 | sed 's/# Generated on //')${NC}"
        
        # Apply saved values only if not overridden by command line
        if [ $HAS_O -eq 0 ] && [ -n "$OUTPUT_DIR" ]; then
            OUTPUT_DIR="$OUTPUT_DIR"
        fi
        if [ $HAS_T -eq 0 ] && [ -n "$SLEEP_INTERVAL" ]; then
            SLEEP_INTERVAL="$SLEEP_INTERVAL"
        fi
        if [ $HAS_F -eq 0 ] && [ -n "$FORMAT" ]; then
            FORMAT="$FORMAT"
        fi
        if [ $HAS_Q -eq 0 ] && [ -n "$QUALITY" ]; then
            QUALITY="$QUALITY"
        fi
        if [ $HAS_A -eq 0 ] && [ -n "$ENABLE_ARCHIVE" ]; then
            ENABLE_ARCHIVE="$ENABLE_ARCHIVE"
        fi
        
        echo -e "${GREEN}[INFO] Using saved settings:${NC}"
        echo "  Playlist URL: $PLAYLIST_URL"
        echo "  Format: $FORMAT"
        echo "  Quality: $QUALITY"
        echo "  Delay: ${SLEEP_INTERVAL}s"
        echo "  Archive recovery: $( [ "$ENABLE_ARCHIVE" = true ] && echo "ON" || echo "OFF" )"
        echo ""
    else
        echo -e "${RED}ERROR: Playlist URL is required on first run${NC}"
        show_help
        exit 1
    fi
fi

# Validate quality
if [[ ! "$QUALITY" =~ ^(low|mid|high)$ ]]; then
    echo -e "${RED}ERROR: Quality must be low, mid, or high${NC}"
    exit 1
fi

# Clean URL if provided
if [ -n "$PLAYLIST_URL" ]; then
    PLAYLIST_URL=$(clean_playlist_url "$PLAYLIST_URL")
fi

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

# Set quality parameters
set_quality_params "$QUALITY" "$FORMAT"

# ========== CREATE OUTPUT DIRECTORY ==========
mkdir -p "$OUTPUT_DIR"

# ========== SAVE CONFIGURATION (if -p was provided) ==========
if [ $HAS_P -eq 1 ]; then
    CONFIG_PATH="$OUTPUT_DIR/$CONFIG_FILE"
    save_config "$CONFIG_PATH" "$PLAYLIST_URL" "$OUTPUT_DIR" "$SLEEP_INTERVAL" "$FORMAT" "$QUALITY" "$ENABLE_ARCHIVE"
fi

cd "$OUTPUT_DIR" || exit 1

# Set up hidden log files
LOG_FILE=".downloaded_ids.txt"
FAILED_LOG=".failed_ids.txt"
RECOVERED_LOG=".recovered_ids.txt"
PERMANENTLY_FAILED_LOG=".permanently_failed_ids.txt"
ARCHIVE_DIR=".archive_recovered"
VIDEO_IDS_FILE=".playlist_videos.txt"

# Initialize files
touch "$LOG_FILE" "$FAILED_LOG" "$RECOVERED_LOG" "$PERMANENTLY_FAILED_LOG"

echo -e "${BLUE}Log files: $LOG_FILE, $PERMANENTLY_FAILED_LOG, etc.${NC}"

# Simple mark functions
mark_downloaded() { 
    echo "$1" >> "$LOG_FILE"
    sync
}

mark_recovered() { 
    echo "$1" >> "$RECOVERED_LOG"
    sync
}

mark_failed() { 
    echo "$1" >> "$FAILED_LOG"
    sync
}

mark_permanently_failed() { 
    echo "$1" >> "$PERMANENTLY_FAILED_LOG"
    sync
}

# Clean exit
cleanup() {
    echo -e "\n\n${YELLOW}Interrupted. Progress saved. Run again to resume.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Archive search function (only used if -a is enabled)
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

# ========== EXTRACT VIDEO IDs ==========
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Tak Playlist Downloader${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
echo "Quality: $QUALITY"
echo "Delay: ${SLEEP_INTERVAL}s"
echo "Archive recovery: $( [ "$ENABLE_ARCHIVE" = true ] && echo "ON" || echo "OFF" )"
echo ""

# Check internet
if ! check_internet; then
    wait_for_internet
fi

echo -e "${BLUE}Fetching playlist...${NC}"

# Extract video IDs
> "$VIDEO_IDS_FILE"
yt-dlp --cookies-from-browser firefox \
       --flat-playlist --print "%(id)s" \
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

# Calculate totals
TOTAL=$(wc -l < "$VIDEO_IDS_FILE")

if [ "$ENABLE_ARCHIVE" = true ]; then
    DOWNLOADED_COUNT=$(grep -Fxf -- "$VIDEO_IDS_FILE" "$LOG_FILE" 2>/dev/null | wc -l)
    RECOVERED_COUNT=$(grep -Fxf -- "$VIDEO_IDS_FILE" "$RECOVERED_LOG" 2>/dev/null | wc -l)
    PERMANENTLY_FAILED_COUNT=$(grep -Fxf -- "$VIDEO_IDS_FILE" "$PERMANENTLY_FAILED_LOG" 2>/dev/null | wc -l)
    REMAINING=$((TOTAL - DOWNLOADED_COUNT - RECOVERED_COUNT - PERMANENTLY_FAILED_COUNT))
    [ $REMAINING -lt 0 ] && REMAINING=0
    
    echo "Total videos: $TOTAL"
    echo "Downloaded (in log): $DOWNLOADED_COUNT"
    echo "Recovered from archives: $RECOVERED_COUNT"
    echo "Permanently failed: $PERMANENTLY_FAILED_COUNT"
    echo "Remaining: $REMAINING"
else
    DOWNLOADED_COUNT=$(grep -Fxf -- "$VIDEO_IDS_FILE" "$LOG_FILE" 2>/dev/null | wc -l)
    RECOVERED_COUNT=0
    PERMANENTLY_FAILED_COUNT=$(grep -Fxf -- "$VIDEO_IDS_FILE" "$PERMANENTLY_FAILED_LOG" 2>/dev/null | wc -l)
    FAILED_COUNT=$(grep -Fxf -- "$VIDEO_IDS_FILE" "$FAILED_LOG" 2>/dev/null | wc -l)
    REMAINING=$((TOTAL - DOWNLOADED_COUNT - PERMANENTLY_FAILED_COUNT - FAILED_COUNT))
    [ $REMAINING -lt 0 ] && REMAINING=0
    
    echo "Total videos: $TOTAL"
    echo "Downloaded (in log): $DOWNLOADED_COUNT"
    echo "Permanently failed: $PERMANENTLY_FAILED_COUNT"
    echo "Failed (pending retry): $FAILED_COUNT"
    echo "Remaining: $REMAINING"
fi
echo ""

# Verify log file is writable
if [ ! -w "$LOG_FILE" ]; then
    echo -e "${RED}ERROR: Log file not writable: $LOG_FILE${NC}"
    exit 1
fi

# ========== DOWNLOAD LOOP ==========
PROCESSED=0
YOUTUBE_SUCCESS=0
RECOVERED_VIDEOS=0
FAILED_VIDEOS=0
SKIPPED_PERMANENT=0
SKIPPED_ALREADY=0

while IFS= read -r video_id; do
    [ -z "$video_id" ] && continue
    
    # Trim whitespace
    video_id=$(echo "$video_id" | tr -d '[:space:]')
    PROCESSED=$((PROCESSED + 1))
    
    # Check if permanently failed (using -- to handle hyphens)
    if grep -Fxq -- "$video_id" "$PERMANENTLY_FAILED_LOG" 2>/dev/null; then
        echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (permanently failed)"
        SKIPPED_PERMANENT=$((SKIPPED_PERMANENT + 1))
        continue
    fi
    
    # Check if already downloaded (using -- to handle hyphens)
    if grep -Fxq -- "$video_id" "$LOG_FILE" 2>/dev/null; then
        echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (already downloaded)"
        SKIPPED_ALREADY=$((SKIPPED_ALREADY + 1))
        continue
    fi
    
    # Check if already recovered (using -- to handle hyphens)
    if grep -Fxq -- "$video_id" "$RECOVERED_LOG" 2>/dev/null; then
        echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (already recovered)"
        SKIPPED_ALREADY=$((SKIPPED_ALREADY + 1))
        continue
    fi
    
    # If not using archive, skip videos in failed log
    if [ "$ENABLE_ARCHIVE" = false ]; then
        if grep -Fxq -- "$video_id" "$FAILED_LOG" 2>/dev/null; then
            echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (previously failed - will retry later)"
            continue
        fi
    fi
    
    # If we get here, need to download
    echo ""
    echo -e "${YELLOW}[$(printf "%4d" $PROCESSED)/$TOTAL] DOWNLOADING: $video_id${NC}"
    
    if ! check_internet; then
        wait_for_internet
    fi
    
    # Download with yt-dlp
    yt-dlp --cookies-from-browser firefox \
           --extractor-args youtubetab:skip=authcheck \
           $YTDLP_EXTRA_ARGS \
           --embed-thumbnail --add-metadata \
           --output "$OUTPUT_TEMPLATE" \
           --no-overwrites --continue \
           "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Success - added to log${NC}"
        mark_downloaded "$video_id"
        YOUTUBE_SUCCESS=$((YOUTUBE_SUCCESS + 1))
    else
        echo -e "${RED}  ✗ YouTube failed${NC}"
        
        if [ "$ENABLE_ARCHIVE" = true ]; then
            if search_archive "$video_id"; then
                echo -e "${GREEN}  ✓ Recovered from archive!${NC}"
                mark_recovered "$video_id"
                RECOVERED_VIDEOS=$((RECOVERED_VIDEOS + 1))
            else
                echo -e "${RED}  ✗ Not found in any archive${NC}"
                echo -e "${YELLOW}  → Marked as permanently failed (will not retry)${NC}"
                mark_permanently_failed "$video_id"
                FAILED_VIDEOS=$((FAILED_VIDEOS + 1))
            fi
        else
            echo -e "${YELLOW}  → Archive recovery disabled (use -a to enable)${NC}"
            mark_failed "$video_id"
            FAILED_VIDEOS=$((FAILED_VIDEOS + 1))
        fi
    fi
    
    # Delay between downloads
    if [ $SLEEP_INTERVAL -gt 0 ] && [ $PROCESSED -lt $TOTAL ]; then
        echo -e "${BLUE}  Waiting ${SLEEP_INTERVAL}s...${NC}"
        sleep "$SLEEP_INTERVAL"
    fi
done < "$VIDEO_IDS_FILE"

# Ask to run Move-Recovered if archive was enabled
if [ "$ENABLE_ARCHIVE" = true ] && [ -d "$ARCHIVE_DIR" ] && [ -n "$(ls -A "$ARCHIVE_DIR" 2>/dev/null)" ]; then
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
echo -e "${GREEN}COMPLETE!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Total videos: $TOTAL"
echo ""
echo -e "${GREEN}✓ Downloaded: $YOUTUBE_SUCCESS${NC}"
if [ "$ENABLE_ARCHIVE" = true ]; then
    echo -e "${GREEN}✓ Recovered from archives: $RECOVERED_VIDEOS${NC}"
fi
echo -e "${BLUE}○ Skipped (already in log): $SKIPPED_ALREADY${NC}"
echo -e "${BLUE}○ Skipped (permanently failed): $SKIPPED_PERMANENT${NC}"
if [ "$ENABLE_ARCHIVE" = true ]; then
    echo -e "${RED}✗ Permanently failed (not in any archive): $FAILED_VIDEOS${NC}"
else
    echo -e "${RED}✗ Newly failed: $FAILED_VIDEOS${NC}"
fi
echo ""
echo "Files saved to: $OUTPUT_DIR"