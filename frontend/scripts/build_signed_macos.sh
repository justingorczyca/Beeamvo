#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────
# build_signed_macos.sh
#
# Builds the macOS app with a STABLE self-signed signature so the macOS
# Accessibility permission (needed for auto-paste) survives rebuilds.
#
# Run setup_dev_signing.sh ONCE before the first build.
#
# What this does:
#   1. flutter clean
#   2. flutter build macos --release
#   3. Re-sign the produced .app with "Beeamvo Dev"
#      (overwrites the ad-hoc signature that Flutter applies by default)
#   4. Verify the designation is certificate-based (stable), NOT cdhash-based
#
# Usage:
#   ./scripts/build_signed_macos.sh          # clean + build + sign
#   ./scripts/build_signed_macos.sh --skip-clean   # skip flutter clean
# ─────────────────────────────────────────────────────────────────────────
set -e

# Resolve the frontend/ directory (script lives in frontend/scripts/)
cd "$(dirname "$0")/.."

IDENTITY="Beeamvo Dev"
APP="build/macos/Build/Products/Release/Beeamvo.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"

SKIP_CLEAN=0
case "$1" in
  --skip-clean) SKIP_CLEAN=1 ;;
  -h|--help)
    echo "Usage: $0 [--skip-clean]"
    exit 0 ;;
esac

# ── 0. Ensure the signing identity exists ─────────────────────────────────
if ! security find-identity -p codesigning -v 2>/dev/null | grep -q "${IDENTITY}"; then
  echo "✗ Signing identity '${IDENTITY}' not found."
  echo "  Run one-time setup first:  ./scripts/setup_dev_signing.sh"
  exit 1
fi

# ── 1. Clean ──────────────────────────────────────────────────────────────
if [ "${SKIP_CLEAN}" -eq 0 ]; then
  echo "==> flutter clean"
  flutter clean
fi

# ── 2. Build ──────────────────────────────────────────────────────────────
echo "==> flutter build macos --release"
flutter build macos --release

if [ ! -d "${APP}" ]; then
  echo "✗ Build did not produce ${APP}"
  exit 1
fi

# ── 3. Re-sign with the stable self-signed certificate ────────────────────
echo "==> Re-signing '${APP}' with '${IDENTITY}' (stable identity)"
# --force    : overwrite the existing ad-hoc signature
# --deep     : re-sign embedded frameworks/helpers too
# --entitlements : preserve the existing release entitlements
codesign --force \
         --sign "${IDENTITY}" \
         --entitlements "${ENTITLEMENTS}" \
         --deep \
         "${APP}"

# ── 4. Verify the designation is stable (certificate/identifier based) ────
echo ""
echo "==> Verify (the 'designated' line is what TCC matches):"
codesign -d --requirements - "${APP}" 2>&1 | grep -i "designated" || true
codesign -dvv "${APP}" 2>&1 | grep -E "Identifier=|Signature=|TeamIdentifier=" || true

echo ""
DESIG=$(codesign -d --requirements - "${APP}" 2>&1)
if echo "${DESIG}" | grep -qi "cdhash"; then
  echo "⚠️  Designation still contains 'cdhash' — TCC may still reset on rebuild."
  echo "    The re-sign likely did not take. Re-run setup_dev_signing.sh."
else
  echo "✓ Designation is certificate/identifier-based → permission will persist across rebuilds."
fi

echo ""
echo "✓ Done: ${APP}"
echo "  Open with:  open '${APP}'"
