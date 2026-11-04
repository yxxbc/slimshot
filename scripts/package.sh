#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/Slimshot.app"
STAGE="build/package/Slimshot-$VERSION"
OUT="dist/Slimshot-$VERSION.zip"
UPDATE_OUT="dist/Slimshot-$VERSION-update.zip"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found; run make first" >&2
    exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
cp scripts/install.command "$STAGE/"
cp LICENSE "$STAGE/"
cp README.md "$STAGE/"
chmod +x "$STAGE/install.command"

OUT_DIR="$(dirname "$OUT")"
OUT_BASE="$(basename "$OUT")"
UPDATE_BASE="$(basename "$UPDATE_OUT")"

rm -f "$OUT" "$OUT.sha256" "$UPDATE_OUT" "$UPDATE_OUT.sha256"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE" "$OUT"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$UPDATE_OUT"
(cd "$OUT_DIR" && shasum -a 256 "$OUT_BASE" > "$OUT_BASE.sha256")
(cd "$OUT_DIR" && shasum -a 256 "$UPDATE_BASE" > "$UPDATE_BASE.sha256")

echo "created $OUT"
echo "created $OUT.sha256"
echo "created $UPDATE_OUT"
echo "created $UPDATE_OUT.sha256"
