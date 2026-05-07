#!/bin/bash

# NeuralSDR2 Release Build & DMG Packaging Script
# Creates a versioned DMG containing source distribution + docs

set -e

VERSION="1.0.0"
BUILD_NUMBER="1"
APP_NAME="NeuralSDR2"
RELEASE_DIR="./releases"
BUILD_DIR="./build"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
SOURCE_DMG_NAME="${APP_NAME}-v${VERSION}-Source.dmg"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     NeuralSDR2 Release Build v${VERSION}                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Clean
echo "📦 Step 1: Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$RELEASE_DIR"

# Step 2: Prepare DMG contents
echo ""
echo "📁 Step 2: Preparing DMG contents..."

DMG_CONTENTS="$BUILD_DIR/dmg-contents"
mkdir -p "$DMG_CONTENTS/NeuralSDR2-v${VERSION}"

# Copy source code
echo "   Copying source code..."
cp -R src "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"

# Copy documentation
echo "   Copying documentation..."
cp -R docs "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"

# Copy project files
echo "   Copying project files..."
cp Package.swift "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"
cp NeuralSDR2.xcodeproj/project.pbxproj "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/NeuralSDR2.xcodeproj.pbxproj" 2>/dev/null || echo "   (Xcode project optional)"
cp Brewfile "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"
cp README.md "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"
cp LICENSE "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"
cp CHANGELOG.md "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"
cp CONTRIBUTING.md "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"
cp test_hardware.sh "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"
cp build.sh "$DMG_CONTENTS/NeuralSDR2-v${VERSION}/"

# Create Install Instructions
cat > "$DMG_CONTENTS/INSTALL.txt" << EOF
╔══════════════════════════════════════════════════════════╗
║     NeuralSDR2 v${VERSION} - Installation Instructions     ║
╚══════════════════════════════════════════════════════════╝

REQUIREMENTS:
  • macOS 13.0 (Ventura) or later
  • Xcode 15+ installed
  • Homebrew (https://brew.sh)
  • RTL-SDR USB dongle

INSTALLATION STEPS:

1. Install Dependencies:
   cd NeuralSDR2-v${VERSION}
   brew bundle install

2. Test RTL-SDR Hardware:
   ./test_hardware.sh

3. Build the Application:
   swift build -c release

4. Open in Xcode (alternative):
   open NeuralSDR2.xcodeproj

5. Run the Application:
   swift run NeuralSDR2
   OR
   Build and Run from Xcode (Cmd+R)

DOCUMENTATION:
  • User Guide:        docs/USER-GUIDE.md
  • API Reference:     docs/API-REFERENCE.md
  • Architecture:      docs/02-SYSTEM-ARCHITECTURE.md
  • Quick Start:       docs/QUICKSTART.md

FIRST USE:
  1. Connect your RTL-SDR dongle
  2. Launch NeuralSDR2
  3. Grant USB permissions
  4. Click Start to begin receiving
  5. Switch themes with Cmd+T

SUPPORT:
  • GitHub: https://github.com/NeuralSDR/NeuralSDR2
  • Issues: Report bugs on GitHub Issues
  • Docs:   See docs/ folder

Copyright © 2026 NeuralSDR. All rights reserved.
Licensed under GPL v3.
EOF

# Create Applications symlink for DMG
ln -sf /Applications "$DMG_CONTENTS/Applications"

# Copy release notes to DMG
cp "releases/RELEASE-NOTES-v${VERSION}.md" "$DMG_CONTENTS/" 2>/dev/null || true

# Step 3: Create DMG
echo ""
echo "💾 Step 3: Creating DMG..."

hdiutil create \
  -volname "${APP_NAME} v${VERSION}" \
  -srcfolder "$DMG_CONTENTS" \
  -ov \
  -format UDZO \
  "$RELEASE_DIR/$SOURCE_DMG_NAME" 2>&1 | tail -5

# Step 4: Generate checksums
echo ""
echo "🔐 Step 4: Generating checksums..."
cd "$RELEASE_DIR"
shasum -a 256 "$SOURCE_DMG_NAME" > "$SOURCE_DMG_NAME.sha256"
echo "   SHA256: $(cat $SOURCE_DMG_NAME.sha256)"
cd ..

# Step 5: File size
DMG_SIZE=$(du -h "$RELEASE_DIR/$SOURCE_DMG_NAME" | cut -f1)

# Step 6: Update release notes
echo ""
echo "📝 Step 5: Finalizing release notes..."

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║               BUILD COMPLETE                             ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Version:       v${VERSION}"
echo "║  Build Number:  ${BUILD_NUMBER}"
echo "║  DMG File:      $SOURCE_DMG_NAME"
echo "║  DMG Size:      $DMG_SIZE"
echo "║  Location:      $RELEASE_DIR/"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Contents of releases/:"
ls -lh "$RELEASE_DIR"
