#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"
SLEEP_INTERVAL=11
ENABLE_ARCHIVE=false
PLAYLIST_URL=""
FORMAT="mp3"
QUALITY="mid"
BROWSER="firefox"
TAK_DATA_DIR=".TakData"
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ========== PACKAGE CHECK AND INSTALLATION ==========
check_and_install_packages() {
    local missing_packages=()
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi
    
    echo -e "${BLUE}Checking required packages...${NC}"
    
    if ! command -v yt-dlp &> /dev/null; then
        echo -e "${YELLOW}yt-dlp not found. Will install...${NC}"
        missing_packages+=("yt-dlp")
    else
        echo -e "${GREEN}✓ yt-dlp found${NC}"
    fi
    
    if ! command -v ffmpeg &> /dev/null; then
        echo -e "${YELLOW}ffmpeg not found. Will install...${NC}"
        missing_packages+=("ffmpeg")
    else
        echo -e "${GREEN}✓ ffmpeg found${NC}"
    fi
    
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}curl not found. Will install...${NC}"
        missing_packages+=("curl")
    else
        echo -e "${GREEN}✓ curl found${NC}"
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}jq not found. Will install...${NC}"
        missing_packages+=("jq")
    else
        echo -e "${GREEN}✓ jq found${NC}"
    fi
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing missing packages: ${missing_packages[*]}${NC}"
        
        case "$OS" in
            ubuntu|debian)
                sudo apt update
                sudo apt install -y "${missing_packages[@]}"
                ;;
            fedora|rhel|centos)
                sudo dnf install -y "${missing_packages[@]}"
                ;;
            arch|manjaro)
                sudo pacman -S --noconfirm "${missing_packages[@]}"
                ;;
            darwin|macos)
                if ! command -v brew &> /dev/null; then
                    echo -e "${RED}Homebrew not found. Please install Homebrew first:${NC}"
                    echo ' /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
                    exit 1
                fi
                brew install "${missing_packages[@]}"
                ;;
            *)
                echo -e "${RED}Unsupported OS. Please install manually: ${missing_packages[*]}${NC}"
                exit 1
                ;;
        esac
        
        for pkg in "${missing_packages[@]}"; do
            if ! command -v "$pkg" &> /dev/null; then
                echo -e "${RED}Failed to install $pkg. Please install manually.${NC}"
                exit 1
            fi
        done
    fi
    
    if [[ " ${missing_packages[*]} " =~ "yt-dlp" ]] && ! command -v yt-dlp &> /dev/null; then
        echo -e "${YELLOW}Installing yt-dlp via pip...${NC}"
        pip3 install yt-dlp --break-system-packages 2>/dev/null || pip3 install yt-dlp
    fi
    
    echo -e "${GREEN}All required packages are installed!${NC}"
    echo ""
}

# ========== DENO INSTALLATION FOR LINUX/MAC ==========
check_and_install_deno() {
    echo -e "${BLUE}Checking for Deno (JavaScript runtime for yt-dlp)...${NC}"
    
    if ! command -v deno &> /dev/null; then
        echo -e "${YELLOW}Deno not found. Installing Deno...${NC}"
        
        curl -fsSL https://deno.land/install.sh | sh
        
        export DENO_INSTALL="$HOME/.deno"
        export PATH="$DENO_INSTALL/bin:$PATH"
        
        if [ -f "$HOME/.bashrc" ]; then
            echo 'export PATH="$HOME/.deno/bin:$PATH"' >> "$HOME/.bashrc"
        elif [ -f "$HOME/.zshrc" ]; then
            echo 'export PATH="$HOME/.deno/bin:$PATH"' >> "$HOME/.zshrc"
        fi
        
        if command -v deno &> /dev/null; then
            echo -e "${GREEN}✓ Deno installed successfully${NC}"
            deno --version | head -1
        else
            echo -e "${RED}✗ Deno installation failed${NC}"
            echo -e "${YELLOW}Please install manually: curl -fsSL https://deno.land/install.sh | sh${NC}"
        fi
    else
        echo -e "${GREEN}✓ Deno found: $(deno --version | head -1)${NC}"
    fi
    echo ""
}

check_and_install_packages
check_and_install_deno

# Function to get TakData directory path
get_takdata_path() {
    local output_dir="$1"
    local takdata_path="${output_dir}/${TAK_DATA_DIR}"
    mkdir -p "$takdata_path"
    echo "$takdata_path"
}

clean_playlist_url() {
    echo "$1" | sed 's/&si=[^&]*//g' | sed 's/?si=[^&]*//g'
}

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
        echo -e "${BLUE}Audio quality: $quality (${format_lower})${NC}"
        
    elif echo "$video_formats" | grep -qw "$format_lower"; then
        case "$quality" in
            low) YTDLP_EXTRA_ARGS="-f worstvideo+worstaudio --merge-output-format ${format_lower}" ;;
            mid) YTDLP_EXTRA_ARGS="-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format ${format_lower}" ;;
            high) YTDLP_EXTRA_ARGS="-f bestvideo+bestaudio --merge-output-format ${format_lower}" ;;
            *) YTDLP_EXTRA_ARGS="-f bestvideo+bestaudio --merge-output-format ${format_lower}" ;;
        esac
    fi
}

show_help() {
    echo "Usage: $0 -p PLAYLIST_URL [-o OUTPUT_DIR] [-t SECONDS] [-f FORMAT] [-q QUALITY] [-b BROWSER] [-a] [-h]"
    echo ""
    echo "Required (first run only):"
    echo "  -p URL        YouTube playlist URL"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -t SECONDS    Sleep between downloads (default: 11, 0 = no delay)"
    echo "  -f FORMAT     Output format: mp3, m4a, opus, flac, mp4, webm, etc. (default: mp3)"
    echo "  -q QUALITY    Quality: low, mid, high (default: mid)"
    echo "  -b BROWSER    Browser for cookies: firefox, chrome, chromium, brave, edge, opera, vivaldi, safari, none (default: firefox)"
    echo "  -a            Enable archive recovery for deleted videos"
    echo "  -h            Show this help"
    echo ""
    echo "Note: Settings and logs are stored in '${TAK_DATA_DIR}' subfolder"
}

while getopts "p:o:t:f:q:b:ah" opt; do
    case $opt in
        p) PLAYLIST_URL="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) SLEEP_INTERVAL="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        q) QUALITY="$OPTARG" ;;
        b) BROWSER="$OPTARG" ;;
        a) ENABLE_ARCHIVE=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

HAS_P=0; HAS_O=0; HAS_T=0; HAS_F=0; HAS_Q=0; HAS_B=0; HAS_A=0
for arg in "$@"; do
    case "$arg" in
        -p) HAS_P=1 ;;
        -o) HAS_O=1 ;;
        -t) HAS_T=1 ;;
        -f) HAS_F=1 ;;
        -q) HAS_Q=1 ;;
        -b) HAS_B=1 ;;
        -a) HAS_A=1 ;;
    esac
done

if [ $HAS_P -eq 0 ]; then
    TAK_DATA_PATH="${OUTPUT_DIR}/${TAK_DATA_DIR}"
    CONFIG_FILE="${TAK_DATA_PATH}/download_config.json"
    
    if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
        PLAYLIST_URL=$(jq -r '.PlaylistUrl' "$CONFIG_FILE")
        [ $HAS_O -eq 0 ] && OUTPUT_DIR=$(jq -r '.OutputDir' "$CONFIG_FILE")
        [ $HAS_T -eq 0 ] && SLEEP_INTERVAL=$(jq -r '.SleepInterval' "$CONFIG_FILE")
        [ $HAS_F -eq 0 ] && FORMAT=$(jq -r '.Format' "$CONFIG_FILE")
        [ $HAS_Q -eq 0 ] && QUALITY=$(jq -r '.Quality' "$CONFIG_FILE")
        [ $HAS_B -eq 0 ] && BROWSER=$(jq -r '.Browser' "$CONFIG_FILE")
        [ $HAS_A -eq 0 ] && ENABLE_ARCHIVE=$(jq -r '.EnableArchive' "$CONFIG_FILE")
        LAST_UPDATED=$(jq -r '.LastUpdated' "$CONFIG_FILE")
        
        echo -e "${GREEN}[INFO] Found saved configuration from: $LAST_UPDATED${NC}"
        echo -e "${GREEN}[INFO] Using saved settings:${NC}"
        echo "  Playlist URL: $PLAYLIST_URL"
        echo "  Format: $FORMAT"
        echo "  Quality: $QUALITY"
        echo "  Browser: $BROWSER"
        echo "  Delay: ${SLEEP_INTERVAL}s"
        echo "  Archive recovery: $( [ "$ENABLE_ARCHIVE" = true ] && echo "ON" || echo "OFF" )"
        echo ""
    elif [ -f "$CONFIG_FILE" ] && ! command -v jq &>/dev/null; then
        echo -e "${RED}ERROR: jq is required to parse saved configuration${NC}"
        echo "Please install jq: sudo apt install jq"
        exit 1
    else
        echo -e "${RED}ERROR: Playlist URL is required on first run${NC}"
        show_help
        exit 1
    fi
fi

if [[ ! "$QUALITY" =~ ^(low|mid|high)$ ]]; then
    echo -e "${RED}ERROR: Quality must be low, mid, or high${NC}"
    exit 1
fi

if [ -n "$PLAYLIST_URL" ]; then
    PLAYLIST_URL=$(clean_playlist_url "$PLAYLIST_URL")
fi

if ! [[ "$SLEEP_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Sleep interval must be a number${NC}"
    exit 1
fi

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

mkdir -p "$OUTPUT_DIR"

if [ $HAS_P -eq 1 ]; then
    TAK_DATA_PATH="${OUTPUT_DIR}/${TAK_DATA_DIR}"
    mkdir -p "$TAK_DATA_PATH"
    CONFIG_FILE="${TAK_DATA_PATH}/download_config.json"
    
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
    echo -e "${BLUE}Configuration saved to: $CONFIG_FILE${NC}"
fi

cd "$OUTPUT_DIR" || exit 1

TAK_DATA_PATH="${OUTPUT_DIR}/${TAK_DATA_DIR}"
mkdir -p "$TAK_DATA_PATH"

LOG_FILE="${TAK_DATA_PATH}/downloaded_ids.txt"
FAILED_LOG="${TAK_DATA_PATH}/failed_ids.txt"
RECOVERED_LOG="${TAK_DATA_PATH}/recovered_ids.txt"
PERMANENTLY_FAILED_LOG="${TAK_DATA_PATH}/permanently_failed_ids.txt"
ARCHIVE_DIR="${TAK_DATA_PATH}/archive_recovered"
VIDEO_IDS_FILE="${TAK_DATA_PATH}/playlist_videos.txt"

touch "$LOG_FILE" "$FAILED_LOG" "$RECOVERED_LOG" "$PERMANENTLY_FAILED_LOG"

echo -e "${BLUE}TakData directory: $TAK_DATA_PATH${NC}"
echo -e "${BLUE}Log files stored in TakData subfolder${NC}"

mark_downloaded() { echo "$1" >> "$LOG_FILE"; sync; }
mark_recovered() { echo "$1" >> "$RECOVERED_LOG"; sync; }
mark_failed() { echo "$1" >> "$FAILED_LOG"; sync; }
mark_permanently_failed() { echo "$1" >> "$PERMANENTLY_FAILED_LOG"; sync; }

cleanup() {
    echo -e "\n\n${YELLOW}Interrupted. Progress saved. Run again to resume.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# ========== ARCHIVE SEARCH VIA AGGREGATOR API ==========
search_archive() {
    local video_id="$1"
    local api_url="https://findyoutubevideo.thetechrobo.ca/api/v5/${video_id}"
    
    echo -e "${BLUE}  → Querying archive aggregator for $video_id...${NC}"
    
    # Fetch the JSON response
    local response
    response=$(curl -sL --max-time 30 "$api_url" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo -e "${RED}     ✗ No response from aggregator API${NC}"
        return 1
    fi
    
    # Check if the API returned an error status
    local status
    status=$(echo "$response" | jq -r '.status // "ok"' 2>/dev/null)
    if [ "$status" = "bad.id" ]; then
        echo -e "${RED}     ✗ Invalid video ID${NC}"
        return 1
    fi
    
    # Check the verdict to see if a full video was found
    local video_found
    video_found=$(echo "$response" | jq -r '.verdict.video // false' 2>/dev/null)
    
    if [ "$video_found" != "true" ]; then
        echo -e "${YELLOW}     ✗ No full video found in any archive${NC}"
        # Optionally, you could check for metadata here: .verdict.metaonly
        return 1
    fi
    
    echo -e "${GREEN}     ✓ Video found in archives!${NC}"
    
    # Extract the first available download URL from the keys array
    # The structure is: keys[] -> select(archived == true) -> available[] -> url
    local download_url
    download_url=$(echo "$response" | jq -r '
        .keys[]? 
        | select(.archived == true) 
        | .available[]? 
        | .url 
        | select(. != null)
    ' 2>/dev/null | head -n 1)
    
    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        echo -e "${RED}     ✗ Found verdict but no direct download URL${NC}"
        return 1
    fi
    
    echo -e "${BLUE}     → Downloading from archive...${NC}"
    mkdir -p "$ARCHIVE_DIR"
    yt-dlp --no-warnings --no-playlist \
           --output "$ARCHIVE_DIR/%(uploader)s - %(title)s.%(ext)s" \
           "$download_url" 2>/dev/null && return 0
    
    echo -e "${RED}     ✗ Download from archive failed${NC}"
    return 1
}

# ========== EXTRACT VIDEO IDs ==========
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Tak Playlist Downloader${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "TakData directory: $TAK_DATA_PATH"
echo "Format: $FORMAT_LOWER ($DOWNLOAD_TYPE)"
echo "Quality: $QUALITY"
echo "Browser: $BROWSER"
echo "Delay: ${SLEEP_INTERVAL}s"
echo "Archive recovery: $( [ "$ENABLE_ARCHIVE" = true ] && echo "ON" || echo "OFF" )"
echo ""

if ! check_internet; then
    wait_for_internet
fi

echo -e "${BLUE}Fetching playlist...${NC}"

> "$VIDEO_IDS_FILE"
if [ "$BROWSER" != "none" ]; then
    yt-dlp --cookies-from-browser "$BROWSER" \
           --flat-playlist --print "%(id)s" \
           "$PLAYLIST_URL" >> "$VIDEO_IDS_FILE" 2>/dev/null
else
    yt-dlp --flat-playlist --print "%(id)s" \
           "$PLAYLIST_URL" >> "$VIDEO_IDS_FILE" 2>/dev/null
fi

if [ ! -s "$VIDEO_IDS_FILE" ]; then
    if [ "$BROWSER" != "none" ]; then
        yt-dlp --cookies-from-browser "$BROWSER" \
               --extractor-args youtubetab:skip=authcheck \
               --flat-playlist --print "%(id)s" \
               "$PLAYLIST_URL" >> "$VIDEO_IDS_FILE" 2>/dev/null
    else
        yt-dlp --extractor-args youtubetab:skip=authcheck \
               --flat-playlist --print "%(id)s" \
               "$PLAYLIST_URL" >> "$VIDEO_IDS_FILE" 2>/dev/null
    fi
fi

sed -i '/^$/d' "$VIDEO_IDS_FILE" 2>/dev/null

if [ ! -s "$VIDEO_IDS_FILE" ]; then
    echo -e "${RED}ERROR: Could not extract video IDs${NC}"
    exit 1
fi

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
    
    video_id=$(echo "$video_id" | tr -d '[:space:]')
    PROCESSED=$((PROCESSED + 1))
    
    if grep -Fxq -- "$video_id" "$PERMANENTLY_FAILED_LOG" 2>/dev/null; then
        echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (permanently failed)"
        SKIPPED_PERMANENT=$((SKIPPED_PERMANENT + 1))
        continue
    fi
    
    if grep -Fxq -- "$video_id" "$LOG_FILE" 2>/dev/null; then
        echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (already downloaded)"
        SKIPPED_ALREADY=$((SKIPPED_ALREADY + 1))
        continue
    fi
    
    if grep -Fxq -- "$video_id" "$RECOVERED_LOG" 2>/dev/null; then
        echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (already recovered)"
        SKIPPED_ALREADY=$((SKIPPED_ALREADY + 1))
        continue
    fi
    
    if [ "$ENABLE_ARCHIVE" = false ]; then
        if grep -Fxq -- "$video_id" "$FAILED_LOG" 2>/dev/null; then
            echo "[$(printf "%4d" $PROCESSED)/$TOTAL] SKIP: $video_id (previously failed - will retry later)"
            continue
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}[$(printf "%4d" $PROCESSED)/$TOTAL] DOWNLOADING: $video_id${NC}"
    
    if ! check_internet; then
        wait_for_internet
    fi
    
    if [ "$BROWSER" != "none" ]; then
        yt-dlp --cookies-from-browser "$BROWSER" \
               --extractor-args youtubetab:skip=authcheck \
               $YTDLP_EXTRA_ARGS \
               --embed-thumbnail --add-metadata \
               --output "$OUTPUT_TEMPLATE" \
               --no-overwrites --continue \
               "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1
    else
        yt-dlp --extractor-args youtubetab:skip=authcheck \
               $YTDLP_EXTRA_ARGS \
               --embed-thumbnail --add-metadata \
               --output "$OUTPUT_TEMPLATE" \
               --no-overwrites --continue \
               "https://youtube.com/watch?v=$video_id" > /dev/null 2>&1
    fi
    
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
    
    if [ $SLEEP_INTERVAL -gt 0 ] && [ $PROCESSED -lt $TOTAL ]; then
        echo -e "${BLUE}  Waiting ${SLEEP_INTERVAL}s...${NC}"
        sleep "$SLEEP_INTERVAL"
    fi
done < "$VIDEO_IDS_FILE"

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
echo "Settings and logs saved to: $TAK_DATA_PATH"