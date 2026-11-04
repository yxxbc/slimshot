#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER is required}"
ZIP_PATH="${ZIP_PATH:?ZIP_PATH is required}"
DOWNLOAD_URL="${DOWNLOAD_URL:?DOWNLOAD_URL is required}"
OUTPUT="${OUTPUT:-dist/appcast.xml}"
SPARKLE_DIR="${SPARKLE_DIR:-vendor/sparkle}"
SIGN_UPDATE="$SPARKLE_DIR/bin/sign_update"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-14.0}"

if [ ! -x "$SIGN_UPDATE" ]; then
    echo "error: $SIGN_UPDATE not found; run ./scripts/fetch-sparkle.sh" >&2
    exit 1
fi
if [ ! -f "$ZIP_PATH" ]; then
    echo "error: $ZIP_PATH not found" >&2
    exit 1
fi

TMP_KEY=""
cleanup() {
    if [ -n "$TMP_KEY" ]; then
        rm -f "$TMP_KEY"
    fi
}
trap cleanup EXIT

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    TMP_KEY="$(mktemp)"
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$TMP_KEY"
    chmod 600 "$TMP_KEY"
    PRIVATE_KEY_FILE="$TMP_KEY"
elif [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    PRIVATE_KEY_FILE="$SPARKLE_PRIVATE_KEY_FILE"
else
    PRIVATE_KEY_FILE=""
fi

if [ -n "$PRIVATE_KEY_FILE" ]; then
    SIGNATURE="$("$SIGN_UPDATE" -f "$PRIVATE_KEY_FILE" -p "$ZIP_PATH")"
else
    SIGNATURE="$("$SIGN_UPDATE" -p "$ZIP_PATH")"
fi

if [ -z "$SIGNATURE" ]; then
    echo "error: empty EdDSA signature" >&2
    exit 1
fi

LENGTH="$(stat -f%z "$ZIP_PATH")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
HOMEPAGE_URL="${HOMEPAGE_URL:-https://github.com/${GITHUB_REPOSITORY:-}}"
if [ "$HOMEPAGE_URL" = "https://github.com/" ]; then
    HOMEPAGE_URL="https://github.com"
fi

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Slimshot</title>
    <link>${HOMEPAGE_URL}</link>
    <description>Slimshot updates</description>
    <language>en</language>
    <item>
      <title>Slimshot ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <enclosure url="${DOWNLOAD_URL}"
                 length="${LENGTH}"
                 type="application/octet-stream"
                 sparkle:edSignature="${SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF

echo "created $OUTPUT"
