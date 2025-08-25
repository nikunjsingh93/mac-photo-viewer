#!/bin/bash

# Simple DMG Creation Script for Glass Photo Viewer
# This script creates a DMG from the app in Build/Products/Debug/

# Configuration
APP_NAME="Glass Photo Viewer"
VERSION="1.0.0"
# Find the app in DerivedData
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"
PROJECT_DIR=$(find "$DERIVED_DATA_DIR" -name "*glass_photo_viewer*" -type d | head -1)
APP_PATH="$PROJECT_DIR/Build/Products/Debug/Glass Photos.app"
DMG_FILE="Glass_Photo_Viewer-${VERSION}.dmg"
DMG_DIR="dmg_temp"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Creating DMG for ${APP_NAME} v${VERSION}${NC}"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ App not found at: $APP_PATH${NC}"
    echo -e "${YELLOW}💡 Please build the project first in Xcode (⌘B)${NC}"
    echo -e "${YELLOW}📁 Expected location: $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found app: $APP_PATH${NC}"

# Create temporary directory for DMG
echo -e "${YELLOW}📁 Creating temporary DMG directory...${NC}"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app to DMG directory
cp -R "$APP_PATH" "$DMG_DIR/"

# Create Applications folder alias
echo -e "${YELLOW}🔗 Creating Applications folder alias...${NC}"
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
echo -e "${YELLOW}📦 Creating DMG file...${NC}"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_FILE"

# Clean up
echo -e "${YELLOW}🧹 Cleaning up temporary files...${NC}"
rm -rf "$DMG_DIR"

echo -e "${GREEN}✅ DMG created successfully: $DMG_FILE${NC}"
echo -e "${GREEN}📋 File size: $(du -h "$DMG_FILE" | cut -f1)${NC}"
echo -e "${GREEN}🎯 Ready to upload to GitHub Releases!${NC}"

# Open the DMG to verify
echo -e "${YELLOW}🔍 Opening DMG for verification...${NC}"
open "$DMG_FILE"
