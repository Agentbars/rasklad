#!/bin/zsh
# One-time setup: creates a self-signed "Rasklad Local Signing" code signing certificate
# in your login keychain. build.sh signs with it, so macOS keeps Rasklad's permissions
# across rebuilds. The certificate is not trusted system-wide and signs nothing else.
set -euo pipefail
NAME="Rasklad Local Signing"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists, nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

PASS=$(openssl rand -hex 16)
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/ext.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$PASS" 2>/dev/null
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign

echo "Created \"$NAME\". Now run ./build.sh install and grant permissions once more."
