# macOS Code Signing & Accessibility Permissions

## The Problem

After each new build, macOS may lose the Accessibility permissions grant for Beeamvo. This happens because ad-hoc code signing generates a new random signature on each build, causing macOS to treat each build as a "different app."

## Symptoms

- Auto-paste (global hotkey) stops working after a new build
- System Settings → Privacy & Security → Accessibility no longer shows Beeamvo
- You must manually remove and re-add the app to grant permissions again

## The Solution

Use a persistent self‑signed code signing certificate. This ensures every build is signed with the same identity, so macOS preserves your permissions across builds.

## One-Time Setup

Run the included setup script **once**:

```bash
cd frontend/macos
./setup_codesign.sh
```

This will:
1. Create a self‑signed code signing certificate
2. Import it into your login keychain
3. Update the Xcode project to use it

After running this, rebuild:

```bash
cd ../..
flutter build macos --release
```

## Accessibility permissions should now persist across all future builds!

## Notes

- The certificate is stored in your personal keychain only.
- Temporary key material is created in a restricted `mktemp` directory and removed automatically by the script.
- The certificate is valid for 10 years.
- This is a local development setup — not for distribution.
- For App Store distribution, use an Apple Developer certificate instead.

## Reverting

To revert to ad-hoc signing (you'll lose permission persistence):

```bash
cd frontend/macos
mv Runner.xcodeproj/project.pbxproj.bak Runner.xcodeproj/project.pbxproj
```

## Verification

To check which certificate is being used:

```bash
codesign -dv build/macos/Build/Products/Release/Beeamvo.app
```

With persistent signing, you should see `Authority=com.beeamvo.codesign`.

With ad-hoc signing, you'll see no Authority (just a hash).
