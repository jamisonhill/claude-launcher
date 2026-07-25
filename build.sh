#!/bin/bash
# Builds ClaudeLauncher and wraps the binary in a real macOS .app bundle.
#
#   ./build.sh            build into ./dist/ClaudeLauncher.app
#   ./build.sh --install  also copy it to /Applications
#
# set -e stops the script on the first failure so we never ship a half-built
# bundle; set -u catches typos in variable names.
set -eu

APP_NAME="ClaudeLauncher"
DISPLAY_NAME="Claude Launcher"
BUNDLE_ID="com.jamisonhill.claudelauncher"
VERSION="1.0.0"

cd "$(dirname "$0")"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Compiling (release)…"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
if [ ! -x "$BINARY" ]; then
  echo "Build produced no executable at $BINARY" >&2
  exit 1
fi

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

# LSMinimumSystemVersion must match the platform in Package.swift, or macOS
# will refuse to open the app on older systems with a confusing error.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
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
