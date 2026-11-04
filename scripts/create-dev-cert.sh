#!/bin/bash
set -euo pipefail

CERT_CN="${CERT_CN:-Slimshot Dev}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/slimshot-dev.keychain-db}"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-slimshot-dev}"
P12_PASSWORD="${P12_PASSWORD:-$(openssl rand -hex 16)}"
DAYS="${DAYS:-3650}"

if security find-certificate -c "$CERT_CN" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "identity already exists: $CERT_CN"
    security find-identity -p codesigning "$KEYCHAIN" || true
    exit 0
fi

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
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

echo "created identity: $CERT_CN"
security find-identity -p codesigning "$KEYCHAIN" || true
echo
echo "Use:"
echo "  CODESIGN_IDENTITY=\"$CERT_CN\" CODESIGN_KEYCHAIN=\"$KEYCHAIN\" make"
echo
echo "The certificate is self-signed and not trusted by Gatekeeper."
echo "That is expected; install.command clears the quarantine attribute."
