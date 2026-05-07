#!/bin/bash
# NeuralSDR2 Appcast Generator
# Updates the appcast.xml with new version info, SHA256, and EdDSA signature

set -e

VERSION=""
BUILD_NUMBER=""
DMG_PATH=""
RELEASE_URL="https://github.com/USER/NeuralSDR2/releases"
APPCAST_PATH="distribution/appcast.xml"
SIGNATURE=""
RELEASE_NOTES=""
MIN_SYSTEM_VERSION="13.0"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Required:"
    echo "  --version X.Y.Z          Version string (e.g. 1.1.0)"
    echo "  --build-number N         Build number (sparkle:version)"
    echo "  --dmg PATH               Path to the DMG file"
    echo ""
    echo "Optional:"
    echo "  --signature SIG          EdDSA signature from Sparkle sign_update"
    echo "  --release-notes NOTES    Release notes (HTML supported)"
    echo "  --url URL                Base release URL (default: ${RELEASE_URL})"
    echo "  --output PATH            Output appcast path (default: ${APPCAST_PATH})"
    echo "  --help                   Show this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --version) VERSION="$2"; shift 2 ;;
        --build-number) BUILD_NUMBER="$2"; shift 2 ;;
        --dmg) DMG_PATH="$2"; shift 2 ;;
        --signature) SIGNATURE="$2"; shift 2 ;;
        --release-notes) RELEASE_NOTES="$2"; shift 2 ;;
        --url) RELEASE_URL="$2"; shift 2 ;;
        --output) APPCAST_PATH="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ] || [ -z "$DMG_PATH" ]; then
    echo "❌ --version, --build-number, and --dmg are required"
    usage
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found: $DMG_PATH"
    exit 1
fi

DMG_FILENAME=$(basename "$DMG_PATH")
DMG_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH" 2>/dev/null)
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

if [ -z "$SIGNATURE" ]; then
    if command -v sign_update &>/dev/null; then
        SIGNATURE=$(sign_update "$DMG_PATH" 2>/dev/null || echo "SIGNATURE_HERE")
    else
        SIGNATURE="SIGNATURE_HERE"
        echo "⚠️ No EdDSA signature provided. Use Sparkle's sign_update tool to generate one."
    fi
fi

if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="<h2>NeuralSDR2 v${VERSION}</h2>\n<ul>\n  <li>See release notes for details</li>\n</ul>"
fi

DMG_URL="${RELEASE_URL}/download/v${VERSION}/${DMG_FILENAME}"

ITEM_XML=$(cat <<ITEMEOF
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure url="${DMG_URL}"
                 sparkle:edSignature="${SIGNATURE}"
                 length="${DMG_SIZE}"
                 type="application/octet-stream"
                 sparkle:dsaSignature="${DMG_SHA256}" />
      <description><![CDATA[${RELEASE_NOTES}]]></description>
    </item>
ITEMEOF
)

if [ -f "$APPCAST_PATH" ]; then
    if grep -q "<sparkle:version>${BUILD_NUMBER}</sparkle:version>" "$APPCAST_PATH"; then
        echo "⚠️ Build number ${BUILD_NUMBER} already exists in appcast. Updating..."
    fi

    sed -i.bak "/<language>en<\/language>/a\\
${ITEM_XML}" "$APPCAST_PATH"
    rm -f "${APPCAST_PATH}.bak"
else
    cat > "$APPCAST_PATH" << APPEOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>NeuralSDR2 Changelog</title>
    <link>${RELEASE_URL}</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
${ITEM_XML}
  </channel>
</rss>
APPEOF
fi

echo "✅ Appcast updated: ${APPCAST_PATH}"
echo "   Version: ${VERSION} (build ${BUILD_NUMBER})"
echo "   DMG: ${DMG_FILENAME} (${DMG_SIZE} bytes)"
echo "   SHA256: ${DMG_SHA256}"
echo "   Signature: ${SIGNATURE}"
echo ""
echo "Remember to:"
echo "  1. Replace SIGNATURE_HERE with a real EdDSA signature if needed"
echo "  2. Update the enclosure URL with the actual GitHub username"
echo "  3. Host the appcast.xml on a public HTTPS server"
