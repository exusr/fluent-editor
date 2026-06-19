#!/bin/bash

# Script to download Google Fonts for local bundling
# Fonts are downloaded from the official Google Fonts GitHub repository

set -e

ASSETS_DIR="$(dirname "$0")/../assets/google_fonts"
REPO_URL="https://github.com/google/fonts/raw/main"

# Create assets directory if it doesn't exist
mkdir -p "$ASSETS_DIR"

echo "Downloading Google Fonts to $ASSETS_DIR..."
echo ""

# Array of font families to download (format: "folder_name|FontName")
declare -a FONTS=(
    "ofl/lato|Lato"
    "ofl/poppins|Poppins"
    "ofl/crimsontext|Crimson Text"
    "ofl/titilliumweb|Titillium Web"
    "ofl/firasans|Fira Sans"
    "ofl/barlow|Barlow"
    "ofl/spacemono|Space Mono"
)

download_font() {
    local folder="$1"
    local font_name="$2"
    local target_name="$3"
    
    local url="$REPO_URL/$folder/$font_name"
    local output="$ASSETS_DIR/$target_name"
    
    echo -n "Downloading $target_name... "
    
    if curl -sL -o "$output" "$url" 2>/dev/null; then
        if [ ! -s "$output" ]; then
            rm -f "$output"
            echo "✗ (empty file)"
            return 1
        fi
        # Validate that the file is a real font (TTF magic: 00010000, OTF magic: OTTO)
        local magic
        magic=$(head -c 4 "$output" | xxd -p)
        if [ "$magic" = "00010000" ] || [ "$magic" = "4f54544f" ]; then
            echo "✓"
            return 0
        else
            rm -f "$output"
            echo "✗ (not a valid font file)"
            return 1
        fi
    else
        rm -f "$output"
        echo "✗ (download failed)"
        return 1
    fi
}

# Download fonts
for font_info in "${FONTS[@]}"; do
    IFS='|' read -r folder font_name <<< "$font_info"
    
    # Convert font name for file naming (remove spaces)
    file_base="${font_name// /}"
    
    # Try to download Regular variant first
    # Skip only if a valid font file already exists
    existing=""
    if [ -f "$ASSETS_DIR/${file_base}-Regular.ttf" ]; then existing="$ASSETS_DIR/${file_base}-Regular.ttf"; fi
    if [ -z "$existing" ] && [ -f "$ASSETS_DIR/${file_base}-Regular.otf" ]; then existing="$ASSETS_DIR/${file_base}-Regular.otf"; fi
    if [ -n "$existing" ]; then
        magic=$(head -c 4 "$existing" | xxd -p)
        if [ "$magic" = "00010000" ] || [ "$magic" = "4f54544f" ]; then
            echo "Skipping $font_name (already exists)"
            continue
        else
            echo "Removing corrupt $existing..."
            rm -f "$existing"
        fi
    fi
    
    # Try different file formats and naming conventions
    # Regular
    download_font "$folder" "${font_name// /}-Regular.ttf" "${file_base}-Regular.ttf" || \
    download_font "$folder" "${font_name// /}-Regular.otf" "${file_base}-Regular.otf" || \
    download_font "$folder" "${font_name// /}Regular.ttf" "${file_base}-Regular.ttf" || \
    download_font "$folder" "${font_name// /}[wdth,wght].ttf" "${file_base}-Regular.ttf" || \
    download_font "$folder" "${font_name// /}-[wght].ttf" "${file_base}-Regular.ttf" || \
    true
    
    # Bold
    download_font "$folder" "${font_name// /}-Bold.ttf" "${file_base}-Bold.ttf" || \
    download_font "$folder" "${font_name// /}-Bold.otf" "${file_base}-Bold.otf" || \
    download_font "$folder" "${font_name// /}Bold.ttf" "${file_base}-Bold.ttf" || \
    true
    
    # Italic
    download_font "$folder" "${font_name// /}-Italic.ttf" "${file_base}-Italic.ttf" || \
    download_font "$folder" "${font_name// /}-Italic.otf" "${file_base}-Italic.otf" || \
    download_font "$folder" "${font_name// /}Italic.ttf" "${file_base}-Italic.ttf" || \
    true
    
    # Bold Italic
    download_font "$folder" "${font_name// /}-BoldItalic.ttf" "${file_base}-BoldItalic.ttf" || \
    download_font "$folder" "${font_name// /}-BoldItalic.otf" "${file_base}-BoldItalic.otf" || \
    true
    
done

echo ""
echo "Download complete!"
echo ""
echo "Downloaded fonts:"
ls -1 "$ASSETS_DIR"/*.ttf "$ASSETS_DIR"/*.otf 2>/dev/null | wc -l | xargs echo "Total files:"
echo ""
echo "If some fonts failed to download, you can:"
echo "1. Run this script again to retry failed downloads"
echo "2. Manually download from https://fonts.google.com"
