#!/bin/bash

# ========== CONFIGURATION ==========
OUTPUT_DIR="$HOME/Music/Tak"
SLEEP_INTERVAL=11
ARCHIVE_DIR="$OUTPUT_DIR/archive_recovered"
RECOVERED_LOG="$OUTPUT_DIR/recovered_ids.txt"
DOWNLOADED_LOG="$OUTPUT_DIR/downloaded_ids.txt"
FAILED_LOG="$OUTPUT_DIR/failed_ids.txt"
# ====================================

mkdir -p "$ARCHIVE_DIR"
touch "$RECOVERED_LOG" "$DOWNLOADED_LOG"

cd "$OUTPUT_DIR" || exit 1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Functions
is_recovered() {
    grep -Fxq "$1" "$RECOVERED_LOG" 2>/dev/null
}

is_downloaded() {
    grep -Fxq "$1" "$DOWNLOADED_LOG" 2>/dev/null
}

mark_recovered() {
    echo "$1" >> "$RECOVERED_LOG"
}

mark_downloaded() {
    echo "$1" >> "$DOWNLOADED_LOG"
}

remove_from_failed() {
    local video_id="$1"
    # Create temp file without the video ID
    grep -Fxv "$video_id" "$FAILED_LOG" > "$FAILED_LOG.tmp" 2>/dev/null
    mv "$FAILED_LOG.tmp" "$FAILED_LOG" 2>/dev/null
}

# Enhanced archive search function (same as smart_download.sh)
search_archive() {
    local video_id="$1"
    local output_file="$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s"
    
    echo -e "${BLUE}  → Searching archives for $video_id...${NC}"
    
    # ========== METHOD 1: Check for direct Archive.org upload ==========
    local archive_direct="https://archive.org/details/youtube-$video_id"
    local direct_check=$(curl -s -o /dev/null -w "%{http_code}" "$archive_direct" 2>/dev/null)
    
    if [ "$direct_check" = "200" ]; then
        echo -e "${BLUE}  → Found direct Archive.org entry, attempting download...${NC}"
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$archive_direct" 2>/dev/null && return 0
    fi
    
    # ========== METHOD 2: GhostArchive (best for video files) ==========
    local ghost_url="https://ghostarchive.org/varchive/youtube/$video_id"
    local ghost_check=$(curl -s -o /dev/null -w "%{http_code}" "$ghost_url" 2>/dev/null)
    
    if [ "$ghost_check" = "200" ]; then
        echo -e "${BLUE}  → Found on GhostArchive, attempting download...${NC}"
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$ghost_url" 2>/dev/null && return 0
    fi
    
    # ========== METHOD 3: Wayback Machine with actual video extraction ==========
    echo -e "${BLUE}  → Checking Wayback Machine...${NC}"
    
    # Get the newest capture timestamp
    local wayback_api="https://archive.org/wayback/available?url=https://youtube.com/watch?v=$video_id"
    local wayback_timestamp=$(curl -s "$wayback_api" | grep -oP '"timestamp":"\K[0-9]+' | head -1)
    
    if [ -n "$wayback_timestamp" ]; then
        local wayback_page_url="https://web.archive.org/web/${wayback_timestamp}/https://youtube.com/watch?v=$video_id"
        echo -e "${BLUE}  → Found capture from $wayback_timestamp${NC}"
        
        # Download the archived HTML
        local archived_html=$(curl -s --max-time 30 "$wayback_page_url")
        
        if [ -n "$archived_html" ]; then
            # Try multiple patterns to extract video URLs
            
            # Pattern 1: Direct MP4/WebM URLs in page source
            local video_url=$(echo "$archived_html" | grep -oP 'https?://web\.archive\.org/web/[0-9]+/[^"\'' ]+\.(mp4|webm|m3u8)' | head -1)
            
            # Pattern 2: YouTube googlevideo.com URLs (archived)
            if [ -z "$video_url" ]; then
                video_url=$(echo "$archived_html" | grep -oP 'https?://[^"\'' ]+\.googlevideo\.com/[^"\'' ]+' | head -1)
            fi
            
            # Pattern 3: Base64 encoded video URLs in player config
            if [ -z "$video_url" ]; then
                local player_config=$(echo "$archived_html" | grep -oP 'var ytInitialPlayerResponse = \K\{.+?\}\;' | head -1)
                if [ -n "$player_config" ]; then
                    video_url=$(echo "$player_config" | grep -oP '"url":"[^"]+"' | head -1 | cut -d'"' -f4 | sed 's/\\\//\//g')
                fi
            fi
            
            # Pattern 4: Try iframe embed version
            if [ -z "$video_url" ]; then
                local embed_url="https://web.archive.org/web/${wayback_timestamp}if_/https://www.youtube.com/embed/$video_id"
                echo -e "${BLUE}  → Trying embed player...${NC}"
                yt-dlp --no-warnings \
                       --output "$output_file" \
                       "$embed_url" 2>/dev/null && return 0
            fi
            
            # If we found a video URL, try to download it
            if [ -n "$video_url" ]; then
                echo -e "${BLUE}  → Extracted video URL, downloading...${NC}"
                yt-dlp --no-warnings \
                       --output "$output_file" \
                       "$video_url" 2>/dev/null && return 0
            fi
        fi
    fi
    
    # ========== METHOD 4: Hobune.stream (community video archive) ==========
    local hobune_url="https://hobune.stream/yt/${video_id}.mp4"
    local hobune_check=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$hobune_url" 2>/dev/null)
    
    if [ "$hobune_check" = "200" ]; then
        echo -e "${BLUE}  → Found on Hobune.stream, downloading...${NC}"
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$hobune_url" 2>/dev/null && return 0
    fi
    
    # ========== METHOD 5: Try multiple Wayback Machine timestamps ==========
    echo -e "${BLUE}  → Trying multiple Wayback captures...${NC}"
    
    # Get all timestamps for this video
    local all_timestamps=$(curl -s "https://web.archive.org/cdx/search/cdx?url=youtube.com/watch?v=$video_id&output=json&limit=10" 2>/dev/null | grep -oP '[0-9]{14}' | head -5)
    
    for timestamp in $all_timestamps; do
        local alt_wayback_url="https://web.archive.org/web/${timestamp}/https://youtube.com/watch?v=$video_id"
        echo -e "${BLUE}  → Trying capture from $timestamp...${NC}"
        
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$alt_wayback_url" 2>/dev/null && return 0
        
        # Also try iframe version
        local alt_embed_url="https://web.archive.org/web/${timestamp}if_/https://www.youtube.com/embed/$video_id"
        yt-dlp --no-warnings \
               --output "$output_file" \
               "$alt_embed_url" 2>/dev/null && return 0
        
        sleep 1
    done
    
    return 1
}

# Main retry loop
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Retry Failed Downloads with Archive Search${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "Archive directory: $ARCHIVE_DIR"
echo "Delay between retries: ${SLEEP_INTERVAL}s"
echo ""

if [ ! -f "$FAILED_LOG" ] || [ ! -s "$FAILED_LOG" ]; then
    echo -e "${YELLOW}No failed_ids.txt found or it's empty. Nothing to retry.${NC}"
    exit 1
fi

# Create a list of videos to retry (excluding already recovered)
TEMP_RETRY_LIST="$OUTPUT_DIR/.retry_list_temp.txt"
> "$TEMP_RETRY_LIST"

while IFS= read -r video_id; do
    [ -z "$video_id" ] && continue
    if ! is_recovered "$video_id" && ! is_downloaded "$video_id"; then
        echo "$video_id" >> "$TEMP_RETRY_LIST"
    fi
done < "$FAILED_LOG"

TOTAL=$(wc -l < "$TEMP_RETRY_LIST")

if [ $TOTAL -eq 0 ]; then
    echo -e "${GREEN}All failed videos have been recovered already!${NC}"
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
    
    # Try YouTube first
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
            STILL_FAILED=$((STILL_FAILED + 1))
        fi
    fi
    
    # Delay
    if [ $CURRENT -lt $TOTAL ]; then
        echo -e "${BLUE}  Waiting ${SLEEP_INTERVAL}s...${NC}"
        sleep "$SLEEP_INTERVAL"
    fi
done < "$TEMP_RETRY_LIST"

# Cleanup
rm -f "$TEMP_RETRY_LIST"

# Final summary
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}RETRY COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Total retried: $TOTAL"
echo -e "${GREEN}✓ Downloaded from YouTube: $SUCCESS${NC}"
echo -e "${GREEN}✓ Recovered from archives: $RECOVERED${NC}"
echo -e "${RED}✗ Still failed: $STILL_FAILED${NC}"
echo ""

if [ $STILL_FAILED -gt 0 ]; then
    echo -e "${YELLOW}Remaining failed videos saved to: $FAILED_LOG${NC}"
    echo ""
    echo -e "${CYAN}You can manually try these URLs:${NC}"
    echo "  https://ghostarchive.org/varchive/youtube/VIDEO_ID"
    echo "  https://web.archive.org/web/*/https://youtube.com/watch?v=VIDEO_ID"
    echo "  https://hobune.stream/yt/VIDEO_ID.mp4"
    echo ""
    echo "Or try searching on:"
    echo "  https://filmot.com (search by video ID)"
fi

# Show recently recovered files
if [ $RECOVERED -gt 0 ]; then
    echo ""
    echo -e "${GREEN}Recently recovered files:${NC}"
    ls -lt "$ARCHIVE_DIR" 2>/dev/null | head -6
fi
