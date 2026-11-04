#!/bin/bash
set -euo pipefail

APP="${1:-build/Slimshot.app}"
IDENTITY="${CODESIGN_IDENTITY:-}"
KEYCHAIN="${CODESIGN_KEYCHAIN:-}"

# Local stable identity. It is self-signed and free; its only job is to keep the
# designated requirement identical across rebuilds so macOS keeps the Screen
# Recording grant. An ad-hoc signature changes cdhash on every build, which makes
# TCC treat each build as a brand new app and ask again.
DEFAULT_KEYCHAIN="$HOME/Library/Keychains/slimshot-release.keychain-db"
PASSWORD_FILE="$HOME/Library/Application Support/Slimshot/signing.keychain-password"

if [ ! -d "$APP" ]; then
    echo "error: app bundle not found: $APP" >&2
    exit 1
fi

if [ -z "$IDENTITY" ] && [ -z "$KEYCHAIN" ] && [ -f "$DEFAULT_KEYCHAIN" ]; then
    KEYCHAIN="$DEFAULT_KEYCHAIN"
fi

# Resolve the identity by SHA-1 fingerprint rather than by common name: the CN
# is configurable, and a name that does not match exactly makes codesign fail
# with "no identity found" and silently fall back to ad-hoc.
resolve_identity() {
    local keychain="$1"
    security find-identity -p codesigning "$keychain" 2>/dev/null |
        awk '/^[[:space:]]*[0-9]+\)/ { print $2; exit }'
}

if [ -n "$KEYCHAIN" ] && [ -f "$KEYCHAIN" ]; then
    if [ -f "$PASSWORD_FILE" ]; then
        security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN" >/dev/null 2>&1 || true
    fi
    if [ -z "$IDENTITY" ]; then
        IDENTITY="$(resolve_identity "$KEYCHAIN")"
    fi
fi

if [ -n "$IDENTITY" ]; then
    args=(--force --deep --preserve-metadata=entitlements --sign "$IDENTITY")
    if [ -n "$KEYCHAIN" ]; then
        args+=(--keychain "$KEYCHAIN")
    fi
    echo "codesign: $IDENTITY"
else
    echo "warning: no local signing identity available; signing ad-hoc." >&2
    echo "warning: Screen Recording permission will reset on every rebuild." >&2
    echo "warning: run ./scripts/create-dev-cert.sh once to fix that for good." >&2
    echo "warning: (a self-signed certificate is enough; no paid Apple account needed)" >&2
    args=(--force --deep --preserve-metadata=entitlements --sign -)
fi

codesign "${args[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"
