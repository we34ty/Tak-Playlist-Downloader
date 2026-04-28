#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
FORMAT="mp3"          # Default format
QUALITY="mid"         # Default quality for conversion
CONFIG_FILE=".download_config.txt"
# ===========================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Disable exit on error
set +e

# Function to load saved configuration
load_saved_config() {
    local config_path="$1"
    
    if [ -f "$config_path" ]; then
        echo -e "${BLUE}Loading saved configuration from: $config_path${NC}"
        source "$config_path"
        return 0
    fi
    return 1
}

# Function to save configuration
save_config() {
    local config_path="$1"
    local format="$2"
    local quality="$3"
    
    # Load existing config, then update specific values
    if [ -f "$config_path" ]; then
        source "$config_path"
    fi
    
    # Update with new values (only if provided)
    [ -n "$format" ] && FORMAT="$format"
    [ -n "$quality" ] && QUALITY="$quality"
    
    cat > "$config_path" << EOF
# Tak Playlist Downloader Configuration
# Generated on $(date '+%Y-%m-%d %H:%M:%S')
PLAYLIST_URL="$PLAYLIST_URL"
OUTPUT_DIR="$OUTPUT_DIR"
SLEEP_INTERVAL=$SLEEP_INTERVAL
FORMAT="$FORMAT"
QUALITY="$QUALITY"
ENABLE_ARCHIVE=$ENABLE_ARCHIVE
EOF
    echo -e "${BLUE}Configuration updated in: $config_path${NC}"
}

# Set quality parameters for ffmpeg
set_quality_params() {
    local quality="$1"
    case "$quality" in
        low)
            AUDIO_BITRATE="96k"
            VIDEO_CRF="28"
            ;;
        mid)
            AUDIO_BITRATE="192k"
            VIDEO_CRF="23"
            ;;
        high)
            AUDIO_BITRATE="320k"
            VIDEO_CRF="18"
            ;;
        *)
            AUDIO_BITRATE="192k"
            VIDEO_CRF="23"
            ;;
    esac
    echo -e "${BLUE}Conversion quality: $quality (audio: ${AUDIO_BITRATE})${NC}"
}

# Help function
show_help() {
    echo "Usage: $0 [-o OUTPUT_DIR] [-f FORMAT] [-q QUALITY] [-h]"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -f FORMAT     Target format for conversion (default: mp3)"
    echo "  -q QUALITY    Quality: low, mid, high (default: mid)"
    echo "  -h            Show this help message"
    echo ""
    echo "Note: This script shares configuration with Download-Playlist.sh"
    echo "      Settings from .download_config.txt will be used if present."
}

# Parse arguments
while getopts "o:f:q:h" opt; do
    case $opt in
        o) OUTPUT_DIR="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        q) QUALITY="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Track which arguments were explicitly provided
HAS_O=0
HAS_F=0
HAS_Q=0

for arg in "$@"; do
    case "$arg" in
        -o) HAS_O=1 ;;
        -f) HAS_F=1 ;;
        -q) HAS_Q=1 ;;
    esac
done

# ========== LOAD SAVED CONFIGURATION ==========
CONFIG_PATH="$OUTPUT_DIR/$CONFIG_FILE"
if [ -f "$CONFIG_PATH" ]; then
    load_saved_config "$CONFIG_PATH"
    
    # Apply saved values only if not overridden by command line
    if [ $HAS_O -eq 0 ] && [ -n "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="$OUTPUT_DIR"
    fi
    if [ $HAS_F -eq 0 ] && [ -n "$FORMAT" ]; then
        FORMAT="$FORMAT"
    fi
    if [ $HAS_Q -eq 0 ] && [ -n "$QUALITY" ]; then
        QUALITY="$QUALITY"
    fi
    
    echo -e "${GREEN}[INFO] Using saved settings from: $CONFIG_PATH${NC}"
    echo "  Format: $FORMAT"
    echo "  Quality: $QUALITY"
    echo ""
fi

# Validate quality
if [[ ! "$QUALITY" =~ ^(low|mid|high)$ ]]; then
    echo -e "${RED}ERROR: Quality must be low, mid, or high${NC}"
    exit 1
fi

# Validate format
FORMAT_LOWER=$(echo "$FORMAT" | tr '[:upper:]' '[:lower:]')
AUDIO_FORMATS="mp3 m4a aac flac wav opus"
VIDEO_FORMATS="mp4 webm mkv avi mov"

if echo "$AUDIO_FORMATS" | grep -qw "$FORMAT_LOWER"; then
    CONVERSION_TYPE="audio"
    echo -e "${BLUE}Target format: $FORMAT_LOWER (audio)${NC}"
elif echo "$VIDEO_FORMATS" | grep -qw "$FORMAT_LOWER"; then
    CONVERSION_TYPE="video"
    echo -e "${BLUE}Target format: $FORMAT_LOWER (video)${NC}"
else
    echo -e "${RED}ERROR: Unsupported format '$FORMAT'${NC}"
    exit 1
fi

# Set quality parameters
set_quality_params "$QUALITY"

# ========== SAVE CONFIGURATION (if any format/quality changes were made) ==========
if [ $HAS_F -eq 1 ] || [ $HAS_Q -eq 1 ]; then
    save_config "$CONFIG_PATH" "$FORMAT" "$QUALITY"
fi

# ========== CHANGE TO OUTPUT DIRECTORY ==========
cd "$OUTPUT_DIR" || exit 1

# Set up hidden paths
ARCHIVE_DIR=".archive_recovered"
LOG_FILE=".recovered_moved.log"

touch "$LOG_FILE"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Archive Recovery Processor${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Source: $ARCHIVE_DIR"
echo "Destination: $OUTPUT_DIR"
echo "Target format: $FORMAT_LOWER"
echo "Quality: $QUALITY"
echo ""

# Check if archive directory exists
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo -e "${YELLOW}Archive directory not found: $ARCHIVE_DIR${NC}"
    exit 1
fi

# Count files
TOTAL_FILES=0
for file in "$ARCHIVE_DIR"/*; do
    if [ -f "$file" ]; then
        case "${file##*.}" in
            mp3|m4a|webm|opus|mp4|flac|wav|aac|mkv|avi|mov)
                TOTAL_FILES=$((TOTAL_FILES + 1))
                ;;
        esac
    fi
done

if [ $TOTAL_FILES -eq 0 ]; then
    echo -e "${YELLOW}No media files found in $ARCHIVE_DIR${NC}"
    exit 0
fi

echo -e "${BLUE}Found $TOTAL_FILES files to process${NC}"
echo ""

PROCESSED=0
CONVERTED=0
FAILED=0

# Build file list into array
FILE_LIST=()
while IFS= read -r -d '' file; do
    FILE_LIST+=("$file")
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f \( \
    -iname "*.mp3" -o \
    -iname "*.m4a" -o \
    -iname "*.webm" -o \
    -iname "*.opus" -o \
    -iname "*.mp4" -o \
    -iname "*.flac" -o \
    -iname "*.wav" -o \
    -iname "*.aac" -o \
    -iname "*.mkv" -o \
    -iname "*.avi" -o \
    -iname "*.mov" \) -print0 2>/dev/null)

# Process each file
for file in "${FILE_LIST[@]}"; do
    PROCESSED=$((PROCESSED + 1))
    filename=$(basename "$file")
    extension="${filename##*.}"
    extension="${extension,,}"
    name_without_ext="${filename%.*}"
    
    echo -e "${CYAN}[$PROCESSED/$TOTAL_FILES] Processing: $filename${NC}"
    
    echo -e "${BLUE}  → Converting $extension to $FORMAT_LOWER...${NC}"
    
    temp_file="${name_without_ext}.$FORMAT_LOWER"
    
    # Handle duplicates
    if [ -f "$temp_file" ]; then
        base="${name_without_ext}"
        counter=1
        while [ -f "${base}_${counter}.$FORMAT_LOWER" ]; do
            counter=$((counter + 1))
        done
        temp_file="${base}_${counter}.$FORMAT_LOWER"
    fi
    
    conversion_success=0
    
    if [[ "$CONVERSION_TYPE" == "audio" ]]; then
        # Audio conversion
        ffmpeg -i "$file" -vn -ar 44100 -ac 2 -b:a "$AUDIO_BITRATE" "$temp_file" -y 2>/dev/null
        [ $? -eq 0 ] && [ -f "$temp_file" ] && [ -s "$temp_file" ] && conversion_success=1
    else
        # Video conversion
        ffmpeg -i "$file" -c:v libx264 -crf "$VIDEO_CRF" -c:a aac -b:a "$AUDIO_BITRATE" "$temp_file" -y 2>/dev/null
        [ $? -eq 0 ] && [ -f "$temp_file" ] && [ -s "$temp_file" ] && conversion_success=1
    fi
    
    if [ $conversion_success -eq 1 ]; then
        echo -e "${GREEN}  ✓ Converted to $FORMAT_LOWER: $(basename "$temp_file")${NC}"
        rm -f "$file" 2>/dev/null
        CONVERTED=$((CONVERTED + 1))
        echo "$temp_file" >> "$LOG_FILE"
    else
        echo -e "${RED}  ✗ Conversion failed for: $filename${NC}"
        FAILED=$((FAILED + 1))
        echo "FAILED: $filename" >> "$LOG_FILE"
    fi
done

# Clean up empty archive directory
if [ -d "$ARCHIVE_DIR" ]; then
    rmdir "$ARCHIVE_DIR" 2>/dev/null
    if [ -d "$ARCHIVE_DIR" ]; then
        remaining=$(ls -1 "$ARCHIVE_DIR" | wc -l)
        if [ $remaining -gt 0 ]; then
            echo -e "${YELLOW}Warning: $remaining files remain in $ARCHIVE_DIR${NC}"
        fi
    fi
fi

# Summary
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}PROCESSING COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Total files processed: $PROCESSED"
echo -e "${GREEN}✓ Converted to $FORMAT_LOWER: $CONVERTED${NC}"
echo -e "${RED}✗ Failed: $FAILED${NC}"
echo ""
echo "Log saved to: $LOG_FILE"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Failed files (check $LOG_FILE for details):${NC}"
    grep "FAILED:" "$LOG_FILE" | tail -5 2>/dev/null
fi