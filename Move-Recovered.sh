#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
FORMAT="mp3"          # Default format (for conversion)
# ===========================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Help function
show_help() {
    echo "Usage: $0 [-o OUTPUT_DIR] [-f FORMAT] [-h]"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -f FORMAT     Target format for conversion (default: mp3)"
    echo "                Audio: mp3, m4a, aac, flac, wav, opus"
    echo "                Video: mp4, webm, mkv, avi, mov"
    echo "  -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -o \"$HOME/Music/Tak\""
    echo "  $0 -f mp4                    # Convert to MP4 video"
    echo "  $0 -f flac -o \"$HOME/Music\" # Convert to FLAC audio"
}

# Parse arguments
while getopts "o:f:h" opt; do
    case $opt in
        o) OUTPUT_DIR="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Validate format
FORMAT_LOWER=$(echo "$FORMAT" | tr '[:upper:]' '[:lower:]')
AUDIO_FORMATS="mp3 m4a aac flac wav opus vorbis"
VIDEO_FORMATS="mp4 webm mkv avi mov"

if echo "$AUDIO_FORMATS" | grep -qw "$FORMAT_LOWER"; then
    CONVERSION_TYPE="audio"
    echo -e "${BLUE}Target format: $FORMAT_LOWER (audio)${NC}"
elif echo "$VIDEO_FORMATS" | grep -qw "$FORMAT_LOWER"; then
    CONVERSION_TYPE="video"
    echo -e "${BLUE}Target format: $FORMAT_LOWER (video)${NC}"
else
    echo -e "${RED}ERROR: Unsupported format '$FORMAT'${NC}"
    echo "Supported audio formats: $AUDIO_FORMATS"
    echo "Supported video formats: $VIDEO_FORMATS"
    exit 1
fi

ARCHIVE_DIR="$OUTPUT_DIR/archive_recovered"
LOG_FILE="$OUTPUT_DIR/recovered_moved.log"

touch "$LOG_FILE"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Archive Recovery Processor${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Source: $ARCHIVE_DIR"
echo "Destination: $OUTPUT_DIR"
echo "Target format: $FORMAT_LOWER"
echo ""

# Check if archive directory exists
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo -e "${YELLOW}Archive directory not found: $ARCHIVE_DIR${NC}"
    exit 1
fi

# Count files
TOTAL_FILES=$(find "$ARCHIVE_DIR" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.webm" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) 2>/dev/null | wc -l)

if [ $TOTAL_FILES -eq 0 ]; then
    echo -e "${YELLOW}No media files found in $ARCHIVE_DIR${NC}"
    exit 0
fi

echo -e "${BLUE}Found $TOTAL_FILES files to process${NC}"
echo ""

PROCESSED=0
CONVERTED=0
MOVED=0
FAILED=0

# Process each file
while IFS= read -r file; do
    PROCESSED=$((PROCESSED + 1))
    filename=$(basename "$file")
    extension="${filename##*.}"
    name_without_ext="${filename%.*}"
    
    echo -e "${YELLOW}[$PROCESSED/$TOTAL_FILES] Processing: $filename${NC}"
    
    # Check if already in target format
    if [[ "${extension,,}" == "$FORMAT_LOWER" ]]; then
        dest_file="$OUTPUT_DIR/$filename"
        
        # Handle duplicates
        if [ -f "$dest_file" ]; then
            base="${name_without_ext}"
            counter=1
            while [ -f "$OUTPUT_DIR/${base}_${counter}.$FORMAT_LOWER" ]; do
                counter=$((counter + 1))
            done
            dest_file="$OUTPUT_DIR/${base}_${counter}.$FORMAT_LOWER"
            echo -e "${BLUE}  → Duplicate, saving as: $(basename "$dest_file")${NC}"
        fi
        
        mv "$file" "$dest_file" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ Moved (already $FORMAT_LOWER)${NC}"
            MOVED=$((MOVED + 1))
            echo "$(basename "$dest_file")" >> "$LOG_FILE"
        else
            echo -e "${RED}  ✗ Failed to move file${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        # Convert to target format
        echo -e "${BLUE}  → Converting $extension to $FORMAT_LOWER...${NC}"
        
        temp_file="$OUTPUT_DIR/${name_without_ext}.$FORMAT_LOWER"
        
        # Handle duplicates
        if [ -f "$temp_file" ]; then
            base="${name_without_ext}"
            counter=1
            while [ -f "$OUTPUT_DIR/${base}_${counter}.$FORMAT_LOWER" ]; do
                counter=$((counter + 1))
            done
            temp_file="$OUTPUT_DIR/${base}_${counter}.$FORMAT_LOWER"
        fi
        
        # Convert based on type
        if [[ "$CONVERSION_TYPE" == "audio" ]]; then
            # Audio conversion
            ffmpeg -i "$file" -vn -ar 44100 -ac 2 -b:a 192k "$temp_file" -y 2>/dev/null
        else
            # Video conversion (remux if possible, re-encode if needed)
            ffmpeg -i "$file" -c copy "$temp_file" -y 2>/dev/null
            # If copy fails, try re-encoding
            if [ $? -ne 0 ]; then
                ffmpeg -i "$file" -c:v libx264 -c:a aac "$temp_file" -y 2>/dev/null
            fi
        fi
        
        if [ $? -eq 0 ] && [ -f "$temp_file" ]; then
            echo -e "${GREEN}  ✓ Converted to $FORMAT_LOWER: $(basename "$temp_file")${NC}"
            rm "$file"
            CONVERTED=$((CONVERTED + 1))
            echo "$(basename "$temp_file")" >> "$LOG_FILE"
        else
            echo -e "${RED}  ✗ Conversion failed${NC}"
            FAILED=$((FAILED + 1))
        fi
    fi
    
done < <(find "$ARCHIVE_DIR" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.webm" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) 2>/dev/null | sort)

# Summary
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}PROCESSING COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Total files processed: $PROCESSED"
echo -e "${GREEN}✓ Files already in $FORMAT_LOWER: $MOVED${NC}"
echo -e "${GREEN}✓ Converted to $FORMAT_LOWER: $CONVERTED${NC}"
echo -e "${RED}✗ Failed: $FAILED${NC}"
echo ""
echo "Log saved to: $LOG_FILE"

# Clean up empty archive directory
if [ -d "$ARCHIVE_DIR" ] && [ -z "$(ls -A "$ARCHIVE_DIR")" ]; then
    rmdir "$ARCHIVE_DIR" 2>/dev/null
    echo -e "${BLUE}Removed empty archive_recovered directory${NC}"
fi
