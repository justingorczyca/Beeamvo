# macOS dev signing — stable Accessibility permission

After every `flutter clean` + rebuild, an **ad-hoc** signed macOS app gets a new
cryptographic fingerprint (CDHash). macOS TCC (the privacy database) keys the
**Accessibility** permission — required for auto-paste — to that fingerprint, so
the toggle silently goes **stale** and paste stops working until you manually
remove + re-add the app in System Settings.

The fix (no Apple Developer ID needed): give the app a **stable signature**
using a self-signed certificate, so TCC matches on the *certificate* instead of
the per-build CDHash.

## One-time setup

```bash
./scripts/setup_dev_signing.sh
```

Creates a self-signed code-signing certificate named **"Beeamvo Dev"** in your
login keychain. (If the automated step is blocked, it prints manual GUI steps —
takes ~30 seconds.) You only do this **once**, ever.

## Build every time with

```bash
./scripts/build_signed_macos.sh              # clean + build + sign
./scripts/build_signed_macos.sh --skip-clean # re-sign faster (no clean)
```

This wraps `flutter build macos --release` and re-signs the produced `.app`
with the stable certificate.

## What to expect

- **First launch** after switching to the stable signature: you'll get *one*
  Accessibility prompt. Grant it.
- **Every rebuild afterwards**: the permission **persists** — no prompts, no
  manual Settings dance, auto-paste just works.

## If a toggle ever still goes stale (rare)

The app has a built-in **"Auto-repair"** action that runs
`tccutil reset Accessibility com.beeamvo.app` (scoped to just Beeamvo) and then
re-fires the native prompt. Find it in:

- the **"Enable Automatic Pasting"** onboarding dialog ("Still not working?
  Auto-repair"), and
- **Settings ▸ Troubleshooting ▸ Permissions**.

## Notes

- This is a **local, machine-specific** signature. It is fine for your own
  development machine. For distribution (other people's Macs), real notarization
  with an Apple Developer ID is still required — but that is unrelated to the
  per-rebuild TCC annoyance.
- The `flutter build macos --release` command on its own (without this script)
  reverts to ad-hoc signing and reintroduces the stale-toggle problem.
