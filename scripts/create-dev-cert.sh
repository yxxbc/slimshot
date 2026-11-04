#!/bin/bash
set -euo pipefail

# Creates a free, self-signed code signing identity for local builds.
#
# Slimshot needs no Apple Developer account. A self-signed certificate is enough
# to give the bundle a stable designated requirement, so macOS keeps the Screen
# Recording grant across rebuilds. Ad-hoc signing cannot do this: its cdhash
# changes on every build and TCC treats each build as a different app.

CERT_CN="${CERT_CN:-Slimshot Dev}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/slimshot-release.keychain-db}"
SUPPORT_DIR="$HOME/Library/Application Support/Slimshot"
PASSWORD_FILE="$SUPPORT_DIR/signing.keychain-password"
DAYS="${DAYS:-3650}"

# Deliberately not `find-identity -v`: a self-signed certificate is reported as
# untrusted (CSSMERR_TP_NOT_TRUSTED) and `-v` filters those out, so `-v` would
# always say "no identity" and this script would mint a new certificate on every
# run. Each new certificate changes the designated requirement and therefore
# throws away the Screen Recording grant.
active_identity_count() {
    security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null |
        grep -c ")$" || true
}

if [ "$(active_identity_count)" -gt 0 ]; then
    echo "identity already usable: $CERT_CN"
    echo "keychain: $KEYCHAIN"
    exit 0
fi

mkdir -p "$SUPPORT_DIR"
chmod 700 "$SUPPORT_DIR"

# Reuse the previous keychain password if we have one, otherwise generate a
# random one and remember it, so `make` can unlock the keychain unattended.
if [ -f "$KEYCHAIN" ] && [ -f "$PASSWORD_FILE" ]; then
    KEYCHAIN_PASSWORD="$(cat "$PASSWORD_FILE")"
elif [ -f "$KEYCHAIN" ]; then
    echo "error: $KEYCHAIN exists but its password is unknown." >&2
    echo "       move it aside and run this script again:" >&2
    echo "       mv \"$KEYCHAIN\" \"$KEYCHAIN.bak\"" >&2
    exit 1
else
    KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -hex 16)}"
fi

P12_PASSWORD="$(openssl rand -hex 16)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3
[dn]
CN = $CERT_CN
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days "$DAYS" -config "$TMP/openssl.cnf" >/dev/null 2>&1

# macOS Security.framework does not accept OpenSSL 3/4's default
# AES-256/SHA-256 PKCS#12 encoding. Prefer the legacy 3DES form, which
# both OpenSSL 1.x and 3/4 can produce.
if ! openssl pkcs12 -export -legacy -out "$TMP/cert.p12" \
        -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -passout pass:"$P12_PASSWORD" -name "$CERT_CN" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1; then
    openssl pkcs12 -export -out "$TMP/cert.p12" \
        -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -passout pass:"$P12_PASSWORD" -name "$CERT_CN" >/dev/null 2>&1
fi

if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
fi
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

printf '%s' "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

# codesign only looks at keychains in the user search list unless --keychain is
# passed, and `make` should not need a password on every build.
existing_list="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')"
if ! printf '%s\n' "$existing_list" | grep -Fxq "$KEYCHAIN"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $existing_list >/dev/null
fi

echo "created identity: $CERT_CN"
echo "keychain: $KEYCHAIN"
security find-identity -p codesigning "$KEYCHAIN" | grep "$CERT_CN" || true
echo
echo "Now a plain \`make\` signs with this identity automatically."
echo "If you need to force it explicitly:"
echo "  CODESIGN_IDENTITY=\"$CERT_CN\" CODESIGN_KEYCHAIN=\"$KEYCHAIN\" make"
echo
echo "The certificate is self-signed, so Gatekeeper does not trust it."
echo "That is expected: install.command clears the quarantine attribute."
