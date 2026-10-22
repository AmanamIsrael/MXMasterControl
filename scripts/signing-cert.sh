#!/bin/sh
# Make "MX Master Control Local Signing", a self-signed code-signing certificate,
# in the login keychain. Run it once per Mac. build-app.sh signs with it when no
# Apple certificate is valid.
#
# macOS keys Input Monitoring and Accessibility to the app's designated
# requirement. A certificate pins that requirement to the certificate, so access
# carries over from build to build.
set -eu
NAME="MX Master Control Local Signing"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "$NAME is already in the keychain."
  exit 0
fi

# macOS's own LibreSSL: Homebrew's OpenSSL 3 writes a .p12 the keychain cannot read.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat >"$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# The .p12 only carries the pair into the keychain. Its password never leaves this script.
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -passout "pass:$PASS" -out "$WORK/pair.p12"
# -T lets codesign use the key without asking each time.
security import "$WORK/pair.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Added $NAME to the login keychain."
