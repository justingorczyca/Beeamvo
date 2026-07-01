#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────
# setup_dev_signing.sh
#
# One-time setup: creates a stable, self-signed CODE-SIGNING certificate in
# your login keychain so the Beeamvo macOS build keeps a STABLE identity
# across rebuilds.
#
# WHY THIS MATTERS:
#   flutter build / flutter clean produces a different binary each time, so an
#   *ad-hoc* signed app gets a new CDHash on every build. macOS TCC (the
#   privacy database) keys Accessibility permission to that CDHash, which is
#   why the toggle silently goes "stale" after a rebuild and auto-paste stops
#   working until you manually remove + re-add the app.
#
#   A self-signed certificate gives the app a stable Designated Requirement
#   (certificate hash instead of CDHash), so the permission PERSISTS across
#   rebuilds — no Developer ID / $99 needed.
#
#   This is the one-time "make it stable" foundation. Run it once, then always
#   build with ./scripts/build_signed_macos.sh
# ─────────────────────────────────────────────────────────────────────────
set -e

IDENTITY="Beeamvo Dev"
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# ── 0. Already present? ───────────────────────────────────────────────────
if security find-identity -p codesigning -v 2>/dev/null | grep -q "${IDENTITY}"; then
  echo "✓ Signing identity '${IDENTITY}' already exists. Nothing to do."
  echo "  Build with: ./scripts/build_signed_macos.sh"
  exit 0
fi

if [ ! -f "${LOGIN_KEYCHAIN}" ]; then
  echo "✗ Login keychain not found at ${LOGIN_KEYCHAIN}"
  print_gui_fallback
  exit 1
fi

echo "Creating self-signed code-signing certificate '${IDENTITY}'…"
echo "(You may see a macOS dialog asking to allow access — click Always Allow.)"
echo ""

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
cd "${WORKDIR}"

# ── 1. Generate key + self-signed cert (valid 10 years) ───────────────────
if ! openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
      -days 3650 -nodes \
      -subj "/CN=${IDENTITY}/O=Beeamvo Dev/C=US" 2>/dev/null; then
  echo "✗ Failed to generate certificate with openssl."
  print_gui_fallback
  exit 1
fi

# ── 2. Package as PKCS#12 ────────────────────────────────────────────────
P12_PASS="beeamvo-$(date +%s)"
if ! openssl pkcs12 -export -inkey key.pem -in cert.pem \
      -out BeeamvoDev.p12 -name "${IDENTITY}" \
      -passout "pass:${P12_PASS}" 2>/dev/null; then
  echo "✗ Failed to package certificate (.p12)."
  print_gui_fallback
  exit 1
fi

# ── 3. Import into login keychain ─────────────────────────────────────────
# -T whitelists codesign/security so they can use the key
if security import BeeamvoDev.p12 -k "${LOGIN_KEYCHAIN}" \
     -P "${P12_PASS}" -T /usr/bin/codesign -T /usr/bin/security; then
  # Best-effort: enable codesign in the key partition list to avoid future
  # per-build password prompts. This may pop a keychain password dialog once.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '' \
     "${LOGIN_KEYCHAIN}" >/dev/null 2>&1 || true
else
  echo ""
  echo "✗ Automated import was blocked or cancelled."
  print_gui_fallback
  exit 1
fi

# ── 4. Verify ─────────────────────────────────────────────────────────────
if security find-identity -p codesigning -v 2>/dev/null | grep -q "${IDENTITY}"; then
  echo ""
  echo "✓ Signing identity '${IDENTITY}' created successfully."
  echo ""
  echo "Next: build with a stable signature:"
  echo "    ./scripts/build_signed_macos.sh"
  echo ""
  echo "First launch after this will still show ONE Accessibility prompt — grant it"
  echo "once. Every rebuild afterwards will keep the permission intact."
  exit 0
else
  echo ""
  echo "✗ Identity could not be verified after import."
  print_gui_fallback
  exit 1
fi

print_gui_fallback() {
  cat <<'EOF'

──────────────────────────────────────────────────────────────────────
  FALLBACK: create the certificate manually (one-time, ~30 seconds)
──────────────────────────────────────────────────────────────────────
1. Open the "Keychain Access" app.
2. Menu bar:  Keychain Access ▸ Certificate Assistant ▸
              Create a Certificate…
3. Fill in:
      Name:            Beeamvo Dev
      Identity Type:   Self-Signed Root
      Certificate Type: Code Signing
4. Click Create. Accept the defaults for the rest.
5. When asked, click "Always Allow" so codesign can use the key.

Then re-run this script to confirm, and build with:
    ./scripts/build_signed_macos.sh
──────────────────────────────────────────────────────────────────────
EOF
}
