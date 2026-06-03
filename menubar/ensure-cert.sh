#!/bin/bash
# Ensures a STABLE self-signed code-signing identity exists in the login keychain
# and prints its name on stdout (all status text goes to stderr). Falls back to
# "-" (ad-hoc) if creation fails. Signing every build with one stable identity is
# what lets macOS keep the Accessibility / Input Monitoring grant across rebuilds
# AND across copies (menubar build vs. /Applications) — so you only grant once.
set -e
CN="TheLongRun Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Already present? (untrusted self-signed identities are NOT listed by -v, so don't use it)
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CN"; then
    echo "$CN"; exit 0
fi

echo "Creating stable code-signing identity \"$CN\" (one time)…" >&2
OPENSSL="/usr/bin/openssl"
BREW_SSL="$(brew --prefix openssl 2>/dev/null)/bin/openssl"
[ -x "$BREW_SSL" ] && OPENSSL="$BREW_SSL"

TMP="$(mktemp -d)"
cat > "$TMP/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CN
[v3]
basicConstraints = critical,CA:FALSE
extendedKeyUsage = critical,codeSigning
keyUsage = critical,digitalSignature
CNF

# Generate key + cert, then import the PEMs directly. We avoid PKCS#12 because
# OpenSSL 3's default p12 MAC algorithm isn't readable by macOS's `security`
# tool ("MAC verification failed"). Separate PEM imports sidestep that entirely;
# the keychain links the key and cert into one identity automatically.
# -T /usr/bin/codesign lets codesign use the key without a GUI prompt each build.
if "$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -days 3650 -nodes -config "$TMP/ext.cnf" >/dev/null 2>&1 \
   && security import "$TMP/key.pem"  -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null 2>&1 \
   && security import "$TMP/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null 2>&1 \
   && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CN"; then
    rm -rf "$TMP"
    echo "  created." >&2
    echo "$CN"
else
    rm -rf "$TMP"
    echo "  ⚠️  could not create identity; falling back to ad-hoc signing." >&2
    echo "-"
fi
