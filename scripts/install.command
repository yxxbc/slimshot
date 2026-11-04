#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/Slimshot.app"
TARGET="${TARGET:-/Applications/Slimshot.app}"

fail() {
    echo "error: $*" >&2
    read -r -p "Press Enter to close..." _ || true
    exit 1
}

if [ ! -d "$APP" ]; then
    fail "Slimshot.app not found next to this script"
fi

if [ -d "$TARGET" ]; then
    ANSWER="$(osascript -e 'display dialog "Slimshot 已安装，是否替换？(Slimshot is already installed. Replace it?)" buttons {"取消 Cancel","替换 Replace"} default button "替换 Replace"' 2>/dev/null || true)"
    case "$ANSWER" in
        *"替换"*|*"Replace"*) ;;
        *) exit 0 ;;
    esac
    rm -rf "$TARGET"
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if ! ditto "$APP" "$TARGET"; then
    fail "could not copy Slimshot.app to /Applications"
fi

xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

if ! codesign --verify --deep --strict "$TARGET"; then
    echo "warning: code signature verification failed" >&2
fi

if [ "${SLIMSHOT_NO_OPEN:-0}" != "1" ]; then
    open "$TARGET"
fi
echo "Slimshot installed to $TARGET"
