#!/bin/bash
# Create a persistent self-signed certificate for Beeamvo
# Run this once to preserve Accessibility permissions across builds
#
# Usage:
#   cd macos
#   ./setup_codesign.sh

set -euo pipefail

CERT_NAME="Beeamvo Code Signing"
CERT_CN="com.beamvo.codesign"
PROJECT_FILE="Runner.xcodeproj/project.pbxproj"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔐 Beeamvo Code Signing Setup"
echo "=============================="
echo ""
echo "This will:"
echo "  1. Create a self-signed code signing certificate"
echo "  2. Import it into your login keychain"
echo "  3. Update the Xcode project to use it"
echo ""
echo "After running this, Accessibility permissions will persist across builds."
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Check if certificate already exists
if security find-certificate -c "$CERT_CN" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || \
   security find-certificate -c "$CERT_CN" ~/Library/Keychains/login.keychain >/dev/null 2>&1; then
  echo ""
  echo "⚠️  Certificate '$CERT_CN' already exists!"
  echo "   Updating project to use it..."
  echo ""
else
  echo "📝 Creating certificate: $CERT_NAME ($CERT_CN)"

  # Keep temporary private-key material in a process-owned directory and
  # always remove it, even if the script is interrupted.
  umask 077
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beeamvo-codesign.XXXXXX")"
  cleanup() {
    rm -rf "$TMP_DIR"
  }
  trap cleanup EXIT INT TERM

  CERT_CONF="$TMP_DIR/cert.conf"
  KEY_FILE="$TMP_DIR/beeamvo.key"
  CSR_FILE="$TMP_DIR/beeamvo.csr"
  CRT_FILE="$TMP_DIR/beeamvo.crt"

  # Create certificate config
  cat > "$CERT_CONF" <<EOF
[req]
default_bits = 2048
distinguished_name = req_distinguished_name
x509_extensions = code_sign
prompt = no

[req_distinguished_name]
CN = $CERT_CN
O = Beeamvo
OU = Development

[code_sign]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

  # Generate private key and certificate. The key is unencrypted so codesign can
  # use it non-interactively after keychain import, but it exists only inside
  # the restrictive temporary directory above.
  openssl req -new -newkey rsa:2048 -nodes -keyout "$KEY_FILE" \
    -out "$CSR_FILE" -config "$CERT_CONF" 2>/dev/null

  openssl x509 -req -days 3650 -in "$CSR_FILE" \
    -signkey "$KEY_FILE" -out "$CRT_FILE" 2>/dev/null

  # Import into login keychain. Restrict private-key access to codesign/security
  # instead of granting all applications access with `-A`.
  security import "$CRT_FILE" -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || \
  security import "$CRT_FILE" -k ~/Library/Keychains/login.keychain \
    -T /usr/bin/codesign -T /usr/bin/security

  security import "$KEY_FILE" -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || \
  security import "$KEY_FILE" -k ~/Library/Keychains/login.keychain \
    -T /usr/bin/codesign -T /usr/bin/security

  # Trust the certificate
  security set-trust -1 -r trustAsRoot -p basic \
    -k ~/Library/Keychains/login.keychain-db -c "$CERT_CN" 2>/dev/null || \
  security set-trust -1 -r trustAsRoot -p basic \
    -k ~/Library/Keychains/login.keychain -c "$CERT_CN"

  cleanup
  trap - EXIT INT TERM

  echo "✓ Certificate created and imported"
fi

# Update Xcode project
echo "📝 Updating Xcode project..."

if [ ! -f "$PROJECT_FILE" ]; then
  echo "⚠️  Could not find $PROJECT_FILE"
  echo "   Please manually update CODE_SIGN_IDENTITY to \"$CERT_CN\""
  exit 1
fi

# Backup the project file once so repeated runs do not overwrite the original.
BACKUP_FILE="${PROJECT_FILE}.bak"
if [ ! -f "$BACKUP_FILE" ]; then
  cp "$PROJECT_FILE" "$BACKUP_FILE"
  echo "✓ Backup created at $BACKUP_FILE"
else
  echo "ℹ️  Existing backup preserved at $BACKUP_FILE"
fi

# Update CODE_SIGN_IDENTITY from ad-hoc signing to the certificate.
if grep -q "CODE_SIGN_IDENTITY = \"$CERT_CN\";" "$PROJECT_FILE"; then
  echo "✓ Xcode project already uses $CERT_CN"
else
  sed -i '' 's/CODE_SIGN_IDENTITY = "-";/CODE_SIGN_IDENTITY = "'"$CERT_CN"'";/g' "$PROJECT_FILE"
  if ! grep -q "CODE_SIGN_IDENTITY = \"$CERT_CN\";" "$PROJECT_FILE"; then
    echo "⚠️  Could not verify CODE_SIGN_IDENTITY update. Please inspect $PROJECT_FILE manually."
    exit 1
  fi
  echo "✓ Xcode project updated"
fi
echo ""
echo "✨ Setup complete!"
echo ""
echo "To rebuild with persistent signing:"
echo "  cd .."
echo "  flutter build macos --release"
echo ""
echo "To revert to ad-hoc signing:"
echo "  cd macos"
echo "  mv Runner.xcodeproj/project.pbxproj.bak Runner.xcodeproj/project.pbxproj"
echo ""
