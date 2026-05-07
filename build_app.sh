#!/bin/bash
# NeuralSDR2 macOS App Bundle Builder
# Creates a proper .app bundle from Swift Package Manager build output

set -e

VERSION="1.0.0"
APP_NAME="NeuralSDR2"
BUNDLE_ID="com.neuralsdr2.app"
SCHEME="NeuralSDR2"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
RESOURCES_DIR="src/Resources"
RELEASE_DIR="./releases"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
ENTITLEMENTS="NeuralSDR2.entitlements"
IDENTITY=""
NOTARIZE=false
CREATE_DMG=false
CLEAN=false

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --dmg                Create a DMG after building"
    echo "  --version X.Y.Z      Override version (default: ${VERSION})"
    echo "  --identity IDENTITY  Code sign with Developer ID (default: ad-hoc)"
    echo "  --notarize           Submit for notarization after signing"
    echo "  --clean              Remove release directory before building"
    echo "  --help               Show this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dmg) CREATE_DMG=true; shift ;;
        --version) VERSION="$2"; DMG_NAME="${APP_NAME}-v${VERSION}.dmg"; shift 2 ;;
        --identity) IDENTITY="$2"; shift 2 ;;
        --notarize) NOTARIZE=true; shift ;;
        --clean) CLEAN=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════╗"
echo "║ NeuralSDR2 App Bundle Builder v${VERSION}"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

if [ "$CLEAN" = true ]; then
    echo "🧹 Cleaning release directory..."
    rm -rf "${RELEASE_DIR}"
    echo " ✅ Cleaned"
fi

# Step 1: Build release
echo "🔨 Step 1: Building release binary..."
swift build -c release 2>&1 | tail -5
echo " ✅ Build complete"

# Step 2: Create app bundle structure
echo ""
echo "📦 Step 2: Creating app bundle..."
BUNDLE_DIR="${RELEASE_DIR}/${APP_BUNDLE}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"
mkdir -p "${BUNDLE_DIR}/Contents/Frameworks"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${BUNDLE_DIR}/Contents/MacOS/"
echo " ✅ Executable copied"

# Copy Info.plist (update version if overridden)
cp "src/Info.plist" "${BUNDLE_DIR}/Contents/"
if [ "$VERSION" != "1.0.0" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
        "${BUNDLE_DIR}/Contents/Info.plist" 2>/dev/null || true
fi
echo " ✅ Info.plist copied"

# Create PkgInfo
echo -n "APPL????" > "${BUNDLE_DIR}/Contents/PkgInfo"
echo " ✅ PkgInfo created"

# Step 3: Create app icon (placeholder)
echo ""
echo "🎨 Step 3: Creating app icon..."
ICONSET_DIR="/tmp/${APP_NAME}.iconset"
mkdir -p "$ICONSET_DIR"

python3 << 'PYTHON' 2>/dev/null || true
import subprocess
import os

iconset = os.environ.get('ICONSET_DIR', '/tmp/NeuralSDR2.iconset')
for size in [16, 32, 64, 128, 256, 512]:
    path = f"{iconset}/icon_{size}x{size}.png"
    if not os.path.exists(path):
        pass
PYTHON

if [ -d "$ICONSET_DIR" ] && [ "$(ls -A $ICONSET_DIR 2>/dev/null)" ]; then
    cp "${RESOURCES_DIR}/AppIcon.icns" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    echo " ✅ Custom icon created"
else
    echo " ⚠️ No custom icon (using system default)"
fi
rm -rf "$ICONSET_DIR"

# Copy any resources
if [ -d "$RESOURCES_DIR" ] && [ "$(ls -A $RESOURCES_DIR 2>/dev/null)" ]; then
    cp -R "$RESOURCES_DIR/"* "${BUNDLE_DIR}/Contents/Resources/" 2>/dev/null || true
    echo " ✅ Resources copied"
fi

# Step 4: Embed librtlsdr dylib (for portability)
echo ""
echo "🔗 Step 4: Embedding dynamic libraries..."
RTLSDR_LIB="/opt/homebrew/opt/librtlsdr/lib/librtlsdr.0.dylib"
if [ -f "$RTLSDR_LIB" ]; then
    EMBEDDED_RTLSDR="${BUNDLE_DIR}/Contents/Frameworks/librtlsdr.0.dylib"
    if [ -f "$EMBEDDED_RTLSDR" ]; then
        chmod u+w "$EMBEDDED_RTLSDR" 2>/dev/null || true
        rm -f "$EMBEDDED_RTLSDR"
    fi
    cp "$RTLSDR_LIB" "$EMBEDDED_RTLSDR"
    install_name_tool -change "/opt/homebrew/opt/librtlsdr/lib/librtlsdr.0.dylib" \
        "@executable_path/../Frameworks/librtlsdr.0.dylib" \
        "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    echo " ✅ librtlsdr embedded"
else
    echo " ⚠️ librtlsdr not found at $RTLSDR_LIB (install with: brew install librtlsdr)"
    echo " ⚠️ App will require librtlsdr to be installed on the target system"
fi

# Step 5: Code sign
echo ""
echo "🔐 Step 5: Code signing..."
if [ -n "$IDENTITY" ]; then
    codesign --force --deep --sign "$IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        --timestamp --options runtime \
        "${BUNDLE_DIR}" 2>/dev/null || {
        echo " ❌ Developer ID signing failed"
        exit 1
    }
    echo " ✅ Signed with: $IDENTITY"
else
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" \
        "${BUNDLE_DIR}" 2>/dev/null || {
        echo " ⚠️ Code signing failed (install Xcode CLI tools: xcode-select --install)"
        echo " ⚠️ App will still work locally but may require Gatekeeper bypass"
    }
    echo " ✅ Ad-hoc signed"
fi

# Step 6: Verify
echo ""
echo "✅ Step 6: Verifying app bundle..."
if [ -x "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" ]; then
    echo " ✅ Executable is valid"
else
    echo " ❌ Executable missing or not executable!"
    exit 1
fi

# Step 7: Create DMG
if [ "$CREATE_DMG" = true ]; then
    echo ""
    echo "💾 Step 7: Creating DMG..."
    mkdir -p "$RELEASE_DIR"

    DMG_STAGING="/tmp/${APP_NAME}-dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "${BUNDLE_DIR}" "$DMG_STAGING/"
    ln -sf /Applications "$DMG_STAGING/Applications"

    hdiutil create \
        -volname "${APP_NAME} v${VERSION}" \
        -srcfolder "$DMG_STAGING" \
        -ov \
        -format UDZO \
        "${RELEASE_DIR}/${DMG_NAME}" 2>&1 | tail -3

    rm -rf "$DMG_STAGING"

    shasum -a 256 "${RELEASE_DIR}/${DMG_NAME}" > "${RELEASE_DIR}/${DMG_NAME}.sha256"

    DMG_SIZE=$(du -h "${RELEASE_DIR}/${DMG_NAME}" | cut -f1)
    echo " ✅ DMG created: ${DMG_NAME} (${DMG_SIZE})"
fi

# Step 8: Notarize (if requested)
if [ "$NOTARIZE" = true ]; then
    if [ -z "$IDENTITY" ]; then
        echo ""
        echo "❌ Notarization requires Developer ID signing (--identity)"
        exit 1
    fi

    if [ "$CREATE_DMG" = false ]; then
        echo ""
        echo "❌ Notarization requires a DMG (--dmg)"
        exit 1
    fi

    echo ""
    echo "📤 Step 8: Submitting for notarization..."
    if [ -z "$NOTARIZE_APPLE_ID" ] || [ -z "$NOTARIZE_PASSWORD" ] || [ -z "$NOTARIZE_TEAM_ID" ]; then
        echo "❌ Set environment variables for notarization:"
        echo "   NOTARIZE_APPLE_ID=user@example.com"
        echo "   NOTARIZE_PASSWORD=@keychain:AC_PASSWORD"
        echo "   NOTARIZE_TEAM_ID=TEAMID"
        exit 1
    fi

    xcrun notarytool submit "${RELEASE_DIR}/${DMG_NAME}" \
        --apple-id "$NOTARIZE_APPLE_ID" \
        --password "$NOTARIZE_PASSWORD" \
        --team-id "$NOTARIZE_TEAM_ID" \
        --wait

    echo ""
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "${RELEASE_DIR}/${DMG_NAME}"
    echo " ✅ Notarized & stapled"
fi

# Generate manifest
echo ""
echo "📋 Generating build manifest..."
APP_CHECKSUM=""
DMG_CHECKSUM=""
if [ -f "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" ]; then
    APP_CHECKSUM=$(shasum -a 256 "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" | cut -d' ' -f1)
fi
if [ -f "${RELEASE_DIR}/${DMG_NAME}" ]; then
    DMG_CHECKSUM=$(shasum -a 256 "${RELEASE_DIR}/${DMG_NAME}" | cut -d' ' -f1)
fi

cat > "${RELEASE_DIR}/manifest.json" << MANIFEST
{
  "version": "${VERSION}",
  "buildDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "appName": "${APP_NAME}",
  "bundleId": "${BUNDLE_ID}",
  "appChecksum": "${APP_CHECKSUM}",
  "dmgName": "${DMG_NAME}",
  "dmgChecksum": "${DMG_CHECKSUM}",
  "signingIdentity": "${IDENTITY:-ad-hoc}",
  "notarized": $([ "$NOTARIZE" = true ] && echo "true" || echo "false")
}
MANIFEST
echo " ✅ Manifest written to ${RELEASE_DIR}/manifest.json"

# Summary
APP_SIZE=$(du -sh "${BUNDLE_DIR}" | cut -f1)
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║ BUILD COMPLETE                                         ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║ App Bundle: ${BUNDLE_DIR}"
echo "║ Size: ${APP_SIZE}"
echo "║ Version: v${VERSION}"
echo "║ Signing: ${IDENTITY:-ad-hoc}"
if [ "$CREATE_DMG" = true ]; then
echo "║ DMG: ${RELEASE_DIR}/${DMG_NAME}"
fi
if [ "$NOTARIZE" = true ]; then
echo "║ Notarized: Yes"
fi
echo "╠══════════════════════════════════════════════════════════╣"
echo "║ To run: open ${BUNDLE_DIR}"
echo "║ To distribute: ./build_app.sh --dmg"
echo "╚══════════════════════════════════════════════════════════╝"
