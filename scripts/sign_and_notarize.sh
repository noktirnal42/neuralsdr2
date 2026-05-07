#!/bin/bash
# NeuralSDR2 Developer ID Signing & Notarization Script
# Signs the app bundle with a Developer ID certificate and submits for Apple notarization

set -e

IDENTITY=""
APPLE_ID=""
PASSWORD=""
TEAM_ID=""
DRY_RUN=false
VERSION="1.0.0"
APP_NAME="NeuralSDR2"
BUNDLE_ID="com.neuralsdr2.app"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
RESOURCES_DIR="src/Resources"
RELEASE_DIR="./releases"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
ENTITLEMENTS="NeuralSDR2.entitlements"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Required for notarization:"
    echo "  --identity \"Developer ID Application: Name (TEAMID)\""
    echo "  --apple-id user@example.com"
    echo "  --password @keychain:AC_PASSWORD"
    echo "  --team-id TEAMID"
    echo ""
    echo "Optional:"
    echo "  --version X.Y.Z       Override version (default: ${VERSION})"
    echo "  --dry-run             Validate all steps without submitting for notarization"
    echo "  --help                Show this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --identity) IDENTITY="$2"; shift 2 ;;
        --apple-id) APPLE_ID="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --version) VERSION="$2"; DMG_NAME="${APP_NAME}-v${VERSION}.dmg"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════╗"
echo "║ NeuralSDR2 Signing & Notarization v${VERSION}"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "❌ Required tool not found: $1"
        echo "   Install Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi
}

echo "🔍 Checking required tools..."
check_tool "codesign"
check_tool "xcrun"
check_tool "hdiutil"
check_tool "swift"
echo " ✅ All required tools available"

if [ -z "$IDENTITY" ]; then
    echo "❌ --identity is required"
    echo "   Provide your Developer ID Application certificate identity, e.g.:"
    echo '   --identity "Developer ID Application: Your Name (TEAMID)"'
    exit 1
fi

if [ "$DRY_RUN" = false ]; then
    if [ -z "$APPLE_ID" ] || [ -z "$PASSWORD" ] || [ -z "$TEAM_ID" ]; then
        echo "❌ Notarization requires --apple-id, --password, and --team-id"
        echo "   Or use --dry-run to skip actual notarization"
        exit 1
    fi
fi

echo ""
echo "🔑 Step 1: Verifying signing identity..."
SEC_IDENTITY=$(security find-identity -v -p codesigning | grep "$IDENTITY" || true)
if [ -z "$SEC_IDENTITY" ]; then
    echo "❌ Signing identity not found in keychain: $IDENTITY"
    echo "   Available identities:"
    security find-identity -v -p codesigning 2>/dev/null || echo "   (none found)"
    exit 1
fi
echo " ✅ Identity found: $IDENTITY"

echo ""
echo "🔨 Step 2: Building release binary..."
swift build -c release 2>&1 | tail -5
echo " ✅ Build complete"

echo ""
echo "📦 Step 3: Creating app bundle..."
BUNDLE_DIR="${RELEASE_DIR}/${APP_BUNDLE}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"
mkdir -p "${BUNDLE_DIR}/Contents/Frameworks"

cp "${BUILD_DIR}/${APP_NAME}" "${BUNDLE_DIR}/Contents/MacOS/"
cp "src/Info.plist" "${BUNDLE_DIR}/Contents/"
echo -n "APPL????" > "${BUNDLE_DIR}/Contents/PkgInfo"

if [ -d "$RESOURCES_DIR" ] && [ "$(ls -A $RESOURCES_DIR 2>/dev/null)" ]; then
    cp -R "$RESOURCES_DIR/"* "${BUNDLE_DIR}/Contents/Resources/" 2>/dev/null || true
fi

RTLSDR_LIB="/opt/homebrew/opt/librtlsdr/lib/librtlsdr.0.dylib"
if [ -f "$RTLSDR_LIB" ]; then
    cp "$RTLSDR_LIB" "${BUNDLE_DIR}/Contents/Frameworks/"
    install_name_tool -change "/opt/homebrew/opt/librtlsdr/lib/librtlsdr.0.dylib" \
        "@executable_path/../Frameworks/librtlsdr.0.dylib" \
        "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    echo " ✅ librtlsdr embedded"
else
    echo " ⚠️ librtlsdr not found at $RTLSDR_LIB"
fi

echo " ✅ App bundle created"

echo ""
echo "🔐 Step 4: Code signing with Developer ID..."
codesign --force --deep --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    --options runtime \
    "${BUNDLE_DIR}"
echo " ✅ Signed with Developer ID (hardened runtime enabled)"

echo ""
echo "✅ Step 5: Verifying signature..."
codesign --verify --deep --strict "${BUNDLE_DIR}"
spctl --assess --type execute "${BUNDLE_DIR}" 2>/dev/null || {
    echo " ⚠️ spctl assessment failed (Gatekeeper may still block the app until notarized)"
}
echo " ✅ Signature verified"

echo ""
echo "💾 Step 6: Creating DMG..."
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
echo " ✅ DMG created: ${DMG_NAME}"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "🧪 DRY RUN: Skipping notarization"
    echo ""
    echo "To notarize for real, run:"
    echo "  xcrun notarytool submit ${RELEASE_DIR}/${DMG_NAME} \\"
    echo "    --apple-id \"${APPLE_ID:-YOUR_APPLE_ID}\" \\"
    echo "    --password \"${PASSWORD:-@keychain:AC_PASSWORD}\" \\"
    echo "    --team-id \"${TEAM_ID:-YOUR_TEAM_ID}\" \\"
    echo "    --wait"
    echo ""
    echo "  xcrun stapler staple ${RELEASE_DIR}/${DMG_NAME}"
else
    echo ""
    echo "📤 Step 7: Submitting for notarization..."
    xcrun notarytool submit "${RELEASE_DIR}/${DMG_NAME}" \
        --apple-id "$APPLE_ID" \
        --password "$PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    echo " ✅ Notarization complete"

    echo ""
    echo "📎 Step 8: Stapling notarization ticket..."
    xcrun stapler staple "${RELEASE_DIR}/${DMG_NAME}"
    echo " ✅ Notarization ticket stapled"
fi

echo ""
echo "🔢 Step 9: Generating SHA256 checksum..."
shasum -a 256 "${RELEASE_DIR}/${DMG_NAME}" > "${RELEASE_DIR}/${DMG_NAME}.sha256"
CHECKSUM=$(cat "${RELEASE_DIR}/${DMG_NAME}.sha256" | cut -d' ' -f1)
echo " ✅ SHA256: ${CHECKSUM}"

DMG_SIZE=$(du -h "${RELEASE_DIR}/${DMG_NAME}" | cut -f1)

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║ SIGNING & NOTARIZATION COMPLETE"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║ DMG: ${RELEASE_DIR}/${DMG_NAME}"
echo "║ Size: ${DMG_SIZE}"
echo "║ Version: v${VERSION}"
echo "║ Identity: ${IDENTITY}"
echo "║ SHA256: ${CHECKSUM}"
if [ "$DRY_RUN" = true ]; then
echo "║ ⚠️ DRY RUN — not notarized"
else
echo "║ ✅ Notarized & Stapled"
fi
echo "╚══════════════════════════════════════════════════════════╝"
