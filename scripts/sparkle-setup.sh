#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_DIR="${SPARKLE_DIR:-vendor/sparkle}"
KEY_FILE="${KEY_FILE:-$PWD/sparkle-private-key}"

./scripts/fetch-sparkle.sh

GENERATE_KEYS="$SPARKLE_DIR/bin/generate_keys"
if [ ! -x "$GENERATE_KEYS" ]; then
    echo "error: $GENERATE_KEYS not found" >&2
    exit 1
fi

echo "Generating/reading the Sparkle EdDSA key (the keychain may prompt)..."
"$GENERATE_KEYS"
PUBLIC_KEY="$("$GENERATE_KEYS" -p)"
"$GENERATE_KEYS" -x "$KEY_FILE"
chmod 600 "$KEY_FILE"

cat <<EOF

Public key:
${PUBLIC_KEY}

Private key exported to:
${KEY_FILE}

Next steps:
1. Add the public key as a GitHub repository variable named SPARKLE_PUBLIC_KEY.
2. Add the contents of ${KEY_FILE} as a GitHub Actions secret named SPARKLE_PRIVATE_KEY.
3. Do not commit ${KEY_FILE}; it is already in .gitignore.

For local testing:
  SPARKLE_PUBLIC_KEY="<public key>" \\
  SPARKLE_FEED_URL="https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml" \\
  make
EOF
