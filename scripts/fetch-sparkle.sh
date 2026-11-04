#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="${SPARKLE_VERSION:-2.7.1}"
SPARKLE_SHA256="${SPARKLE_SHA256:-f7385c3e8c70c37e5928939e6246ac9070757b4b37a5cb558afa1b0d5ef189de}"
SPARKLE_DIR="${SPARKLE_DIR:-vendor/sparkle}"

if [ -d "$SPARKLE_DIR/Sparkle.framework" ] && [ -x "$SPARKLE_DIR/bin/sign_update" ]; then
    echo "Sparkle $SPARKLE_VERSION already present in $SPARKLE_DIR"
    exit 0
fi

URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "downloading Sparkle $SPARKLE_VERSION..."
curl -L --fail --retry 3 --max-time 300 -o "$TMP/sparkle.tar.xz" "$URL"
echo "${SPARKLE_SHA256}  $TMP/sparkle.tar.xz" | shasum -a 256 -c -
tar -xf "$TMP/sparkle.tar.xz" -C "$TMP"

mkdir -p "$SPARKLE_DIR/bin"
rm -rf "$SPARKLE_DIR/Sparkle.framework"
ditto "$TMP/Sparkle.framework" "$SPARKLE_DIR/Sparkle.framework"
cp "$TMP/bin/sign_update" "$SPARKLE_DIR/bin/sign_update"
cp "$TMP/bin/generate_keys" "$SPARKLE_DIR/bin/generate_keys"
cp "$TMP/LICENSE" "$SPARKLE_DIR/LICENSE"
chmod +x "$SPARKLE_DIR/bin/sign_update" "$SPARKLE_DIR/bin/generate_keys"

echo "Sparkle $SPARKLE_VERSION installed in $SPARKLE_DIR"
