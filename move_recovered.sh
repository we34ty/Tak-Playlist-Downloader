#!/bin/bash

# ========== DEFAULT CONFIGURATION ==========
OUTPUT_DIR="$(pwd)"  # Default to current directory
# ===========================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Help function
show_help() {
    echo "Usage: $0 [-o OUTPUT_DIR] [-h]"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: current directory)"
    echo "  -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -o \"$HOME/Music/Tak\""
}

# Parse arguments
while getopts "o:h" opt; do
    case $opt in
        o) OUTPUT_DIR="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

ARCHIVE_DIR="$OUTPUT_DIR/archive_recovered"
LOG_FILE="$OUTPUT_DIR/recovered_moved.log"

touch "$LOG_FILE"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Archive Recovery Processor${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Source: $ARCHIVE_DIR"
echo "Destination: $OUTPUT_DIR"
echo ""

# Check if archive directory exists
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo -e "${YELLOW}Archive directory not found: $ARCHIVE_DIR${NC}"
    exit 1
fi

# Count files
TOTAL_FILES=$(find "$ARCHIVE_DIR" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.webm" -o -iname "*.opus" -o -iname "*.mp4" \) 2>/dev/null | wc -l)

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
    
    # Check if it's already MP3
    if [[ "${extension,,}" == "mp3" ]]; then
        dest_file="$OUTPUT_DIR/$filename"
        
        # Handle duplicates
        if [ -f "$dest_file" ]; then
            base="${name_without_ext}"
            counter=1
            while [ -f "$OUTPUT_DIR/${base}_${counter}.mp3" ]; do
                counter=$((counter + 1))
            done
            dest_file="$OUTPUT_DIR/${base}_${counter}.mp3"
            echo -e "${BLUE}  → Duplicate, saving as: $(basename "$dest_file")${NC}"
        fi
        
        mv "$file" "$dest_file" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ Moved MP3 to main folder${NC}"
            MOVED=$((MOVED + 1))
            echo "$(basename "$dest_file")" >> "$LOG_FILE"
        else
            echo -e "${RED}  ✗ Failed to move file${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        # Convert to MP3
        echo -e "${BLUE}  → Converting $extension to MP3...${NC}"
        
        temp_mp3="$OUTPUT_DIR/${name_without_ext}.mp3"
        
        # Handle duplicates
        if [ -f "$temp_mp3" ]; then
            base="${name_without_ext}"
            counter=1
            while [ -f "$OUTPUT_DIR/${base}_${counter}.mp3" ]; do
                counter=$((counter + 1))
            done
            temp_mp3="$OUTPUT_DIR/${base}_${counter}.mp3"
        fi
        
        # Convert using ffmpeg
        ffmpeg -i "$file" -vn -ar 44100 -ac 2 -b:a 192k "$temp_mp3" -y 2>/dev/null
        
        if [ $? -eq 0 ] && [ -f "$temp_mp3" ]; then
            echo -e "${GREEN}  ✓ Converted to MP3: $(basename "$temp_mp3")${NC}"
            rm "$file"
            CONVERTED=$((CONVERTED + 1))
            echo "$(basename "$temp_mp3")" >> "$LOG_FILE"
        else
            echo -e "${RED}  ✗ Conversion failed${NC}"
            FAILED=$((FAILED + 1))
        fi
    fi
    
done < <(find "$ARCHIVE_DIR" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.webm" -o -iname "*.opus" -o -iname "*.mp4" \) 2>/dev/null | sort)

# Summary
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}PROCESSING COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Total files processed: $PROCESSED"
echo -e "${GREEN}✓ MP3 files moved: $MOVED${NC}"
echo -e "${GREEN}✓ Converted to MP3: $CONVERTED${NC}"
echo -e "${RED}✗ Failed: $FAILED${NC}"
echo ""
echo "Log saved to: $LOG_FILE"

# Clean up empty archive directory
if [ -d "$ARCHIVE_DIR" ] && [ -z "$(ls -A "$ARCHIVE_DIR")" ]; then
    rmdir "$ARCHIVE_DIR" 2>/dev/null
    echo -e "${BLUE}Removed empty archive_recovered directory${NC}"
fi
