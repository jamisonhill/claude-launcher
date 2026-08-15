#!/bin/bash
# Builds the app and wraps the binary in a real macOS .app bundle.
#
#   ./build.sh            build into "./dist/OWL — AI Launcher.app"
#   ./build.sh --install  also copy it to /Applications
#
# PRODUCT_NAME is the SwiftPM target and stays ClaudeLauncher — it names the
# compiled binary and nothing a user ever sees. APP_NAME is the bundle, and is
# very much seen: it's what Finder, the Dock and Spotlight show.
#
# set -e stops the script on the first failure so we never ship a half-built
# bundle; set -u catches typos in variable names.
set -eu

PRODUCT_NAME="ClaudeLauncher"
APP_NAME="OWL — AI Launcher"
DISPLAY_NAME="OWL — AI Launcher"
BUNDLE_ID="com.jamisonhill.claudelauncher"
VERSION="1.0.2"

cd "$(dirname "$0")"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Compiling (release)…"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/$PRODUCT_NAME"
if [ ! -x "$BINARY" ]; then
  echo "Build produced no executable at $BINARY" >&2
  exit 1
fi

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$PRODUCT_NAME"

# Regenerate the icon from source so it can never drift from Icon/make-icon.swift.
if [ -f Icon/make-icon.swift ]; then
  swift Icon/make-icon.swift >/dev/null
  iconutil -c icns Icon/AppIcon.iconset -o Icon/AppIcon.icns
  cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# LSMinimumSystemVersion must match the platform in Package.swift, or macOS
# will refuse to open the app on older systems with a confusing error.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>        <string>$PRODUCT_NAME</string>
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

# Ad-hoc signature. Without it macOS may refuse to launch the app on Apple
# silicon. This is a local-only signature — no developer account needed.
echo "==> Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "==> Built $APP"

if [ "${1:-}" = "--install" ]; then
  echo "==> Installing to /Applications…"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "==> Installed. Open it from Spotlight as \"$DISPLAY_NAME\"."
fi
