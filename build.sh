#!/usr/bin/env bash
# NAKASHA — universal macOS build script.
# Six steps. Fails loudly on any missing artifact.
set -euo pipefail

# Resolve repo root (this script lives at the repo root next to Package.swift).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP_NAME="NAKASHA"
DISPLAY_NAME="NAKASHA"
BUNDLE_ID="net.wolfgangrush.nakasha"
VERSION="0.1.0"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
DMG_DIR="$HOME/Downloads/Dmgs"
DMG_PATH="$DMG_DIR/NAKASHA-v$VERSION.dmg"
DMG_STAGE="$BUILD_DIR/dmg-stage"

step() { echo; echo "[$1/6] $2"; }
fail() { echo "BUILD FAILED: $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
step 1 "Building universal release binary (arm64 + x86_64)"
# ---------------------------------------------------------------------------
swift build --configuration release --arch arm64 --arch x86_64

# Locate the produced executable. SwiftPM on newer toolchains uses the
# .build/apple/Products path; older ones use .build/<config>.
BIN_PATH="$ROOT/.build/apple/Products/Release/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  BIN_PATH="$(swift build --configuration release --show-bin-path)/$APP_NAME"
fi
[[ -x "$BIN_PATH" ]] || fail "Release binary not found at $BIN_PATH"
echo "    binary: $BIN_PATH"

# ---------------------------------------------------------------------------
step 2 "Assembling $APP_NAME.app bundle"
# ---------------------------------------------------------------------------
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>             <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>             <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                   <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>            <string>$DISPLAY_NAME</string>
    <key>CFBundleIconFile</key>               <string>AppIcon</string>
    <key>CFBundleVersion</key>                <string>1</string>
    <key>CFBundleShortVersionString</key>     <string>$VERSION</string>
    <key>CFBundlePackageType</key>            <string>APPL</string>
    <key>LSMinimumSystemVersion</key>         <string>13.0</string>
    <key>NSHighResolutionCapable</key>        <true/>
    <key>NSPrincipalClass</key>               <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>       <string>Apache-2.0 — Copyright 2026 Rushikesh R. Mahajan (wolfgang_rush)</string>
</dict>
</plist>
PLIST

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -f "$RES_DIR/../../Resources/AppIcon.icns" || -f "$ROOT/Resources/AppIcon.icns" ]]; then
  ICNS_SRC="$ROOT/Resources/AppIcon.icns"
  cp "$ICNS_SRC" "$RES_DIR/AppIcon.icns"
  echo "    icon:    copied AppIcon.icns"
else
  echo "    icon:    WARN AppIcon.icns not found in Resources/ — bundle has no icon"
fi

[[ -d "$APP_DIR" ]] || fail "App bundle was not assembled"
[[ -x "$MACOS_DIR/$APP_NAME" ]] || fail "Executable missing inside bundle"
[[ -f "$CONTENTS/Info.plist" ]] || fail "Info.plist missing"
echo "    bundle:  $APP_DIR"

# ---------------------------------------------------------------------------
step 3 "Codesigning the bundle"
# ---------------------------------------------------------------------------
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "    using Developer ID: $DEVELOPER_ID"
  codesign --force --deep \
           --sign "$DEVELOPER_ID" \
           --options runtime \
           --entitlements "$ROOT/entitlements.plist" \
           "$APP_DIR"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "    submitting for notarisation (profile: $NOTARY_PROFILE)"
    ZIP_PATH="$BUILD_DIR/$APP_NAME-notary.zip"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
  else
    echo "    NOTARY_PROFILE not set — skipping notarisation"
  fi
else
  echo "    ad-hoc signing (DEVELOPER_ID not set)"
  codesign --force --deep \
           --sign - \
           --options runtime \
           --entitlements "$ROOT/entitlements.plist" \
           "$APP_DIR"
fi

# ---------------------------------------------------------------------------
step 4 "Verifying signature and that the binary launches"
# ---------------------------------------------------------------------------
codesign --verify --verbose "$APP_DIR"

# Verify the ARCHITECTURES and the ABSENCE OF A NETWORK ENTITLEMENT, and do NOT execute the
# binary. It is a SwiftUI app: running it starts an event loop and the build hangs forever
# with no output, which looks exactly like a compiler that has stalled.
lipo -archs "$MACOS_DIR/$APP_NAME"
if codesign -d --entitlements - "$APP_DIR" 2>&1 | grep -qi "network"; then
  fail "A network entitlement is present. That breaks the product's central promise."
fi
echo "    entitlements: no network entitlement present (verified)"

# Does it actually RUN? A signature that verifies proves nothing about launch.
# On 2026-08-16 a nil-unwrap in a static initialiser crashed the app before it drew
# a window, and every check above still passed — the build was packaged, installed
# and handed over broken. Launch it, wait, and require it to still be alive.
# It must be BACKGROUNDED: a GUI app run in the foreground blocks the build forever,
# which is why the earlier `--help` version of this check had to be removed.
"$MACOS_DIR/$APP_NAME" >/dev/null 2>&1 &
SMOKE_PID=$!
sleep 4
if kill -0 "$SMOKE_PID" 2>/dev/null; then
  kill "$SMOKE_PID" 2>/dev/null || true
  wait "$SMOKE_PID" 2>/dev/null || true
  echo "    launch:       OK — still running after 4s"
else
  wait "$SMOKE_PID" 2>/dev/null; SMOKE_RC=$?
  fail "the app exited on its own (code $SMOKE_RC) instead of staying up — it crashes on launch"
fi

# ---------------------------------------------------------------------------
step 5 "Building distributable DMG into $DMG_DIR"
# ---------------------------------------------------------------------------
mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create -volname "NAKASHA $VERSION" \
               -srcfolder "$DMG_STAGE" \
               -ov -format UDZO \
               "$DMG_PATH"
[[ -f "$DMG_PATH" ]] || fail "DMG was not produced at $DMG_PATH"
echo "    dmg:     $DMG_PATH"

# ---------------------------------------------------------------------------
step 6 "Reporting"
# ---------------------------------------------------------------------------
echo
echo "Done."
echo
echo "  App bundle : $APP_DIR"
echo "  DMG        : $DMG_PATH"
echo
echo "Gatekeeper note (ad-hoc signed, not notarised):"
echo "  macOS will refuse to open the app the first time. The dependable fix, and"
echo "  the one the README leads with:"
echo "      xattr -dr com.apple.quarantine \"$APP_DIR\""
echo
echo "  Without a Terminal: try to open it, then System Settings > Privacy &"
echo "  Security > 'Open Anyway'."
echo
echo "  Right-click > Open is a third option. It worked on older macOS and is no"
echo "  longer dependable on recent versions, so do not lead with it — a user who"
echo "  tries only that concludes the app is broken."
echo
