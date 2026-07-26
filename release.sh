#!/bin/bash
# Builds a signed, notarized, distributable ClaudeLauncher.dmg.
#
#   ./release.sh            build + sign only (no Apple submission)
#   ./release.sh --notarize  also submit to Apple and staple the ticket
#
# Notarization needs credentials stored once in your keychain:
#
#   xcrun notarytool store-credentials claude-launcher \
#     --apple-id "you@example.com" \
#     --team-id HFAWAP3F3Z \
#     --password "app-specific-password-from-appleid.apple.com"
#
# The password is an *app-specific* password, not your Apple ID password.
# Generate one at appleid.apple.com → Sign-In and Security → App-Specific
# Passwords. Nothing here ever sees your real credentials.
set -eu

APP_NAME="ClaudeLauncher"
DISPLAY_NAME="Claude Launcher"
BUNDLE_ID="com.jamisonhill.claudelauncher"
VERSION="${VERSION:-1.0.0}"
TEAM_ID="HFAWAP3F3Z"
SIGN_ID="Developer ID Application: Jamison Hill ($TEAM_ID)"
KEYCHAIN_PROFILE="claude-launcher"

cd "$(dirname "$0")"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/Claude-Launcher-$VERSION.dmg"

echo "==> Compiling (release)…"
swift build -c release
BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP …"
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

# Regenerate the icon from source so it can never drift from Icon/make-icon.swift.
if [ -f Icon/make-icon.swift ]; then
  swift Icon/make-icon.swift >/dev/null
  iconutil -c icns Icon/AppIcon.iconset -o Icon/AppIcon.icns
  cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleIconName</key>          <string>AppIcon</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Hardened Runtime (--options runtime) and a secure timestamp are both
# prerequisites for notarization; Apple rejects submissions without them.
echo "==> Signing with Developer ID…"
codesign --force --deep --timestamp --options runtime \
         --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Building disk image…"
hdiutil create -quiet -volname "$DISPLAY_NAME" -srcfolder "$APP" \
        -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

if [ "${1:-}" = "--notarize" ]; then
  echo "==> Submitting to Apple for notarization (this takes a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait

  echo "==> Stapling the ticket…"
  # Stapling embeds the ticket so Gatekeeper clears the app offline too.
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"

  echo "==> Verifying as Gatekeeper would see it…"
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
fi

echo
echo "==> Done: $DMG"
