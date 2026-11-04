#!/bin/bash
set -euo pipefail

APP="${1:-build/Slimshot.app}"
IDENTITY="${CODESIGN_IDENTITY:-}"
KEYCHAIN="${CODESIGN_KEYCHAIN:-}"

if [ ! -d "$APP" ]; then
    echo "error: app bundle not found: $APP" >&2
    exit 1
fi

if [ -n "$IDENTITY" ]; then
    args=(--force --deep --preserve-metadata=entitlements --sign "$IDENTITY")
    if [ -n "$KEYCHAIN" ]; then
        args+=(--keychain "$KEYCHAIN")
    fi
    echo "codesign: $IDENTITY"
else
    echo "warning: CODESIGN_IDENTITY is not set; signing ad-hoc." >&2
    echo "warning: Screen Recording permission may reset after rebuilds." >&2
    args=(--force --deep --preserve-metadata=entitlements --sign -)
fi

codesign "${args[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
