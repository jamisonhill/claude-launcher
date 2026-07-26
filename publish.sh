#!/bin/bash
# Cuts a release: builds, signs, notarizes, publishes to GitHub Releases, and
# updates the Homebrew cask in the tap.
#
#   ./publish.sh 1.0.1
#
# Prerequisites (one-time):
#   xcrun notarytool store-credentials claude-launcher \
#     --apple-id "you@example.com" --team-id HFAWAP3F3Z --password "app-specific-pw"
#
# set -e stops on the first failure, so a botched notarization can never end up
# published as if it had worked.
set -eu

VERSION="${1:?usage: ./publish.sh <version>   e.g. ./publish.sh 1.0.1}"
REPO="jamisonhill/claude-launcher"
TAP_REPO="jamisonhill/homebrew-tap"
TAP_DIR="${TAP_DIR:-$HOME/Ai/Personal/apps/homebrew-tap}"
DMG="dist/Claude-Launcher-$VERSION.dmg"

cd "$(dirname "$0")"

echo "==> Building and notarizing $VERSION …"
VERSION="$VERSION" ./release.sh --notarize

if [ ! -f "$DMG" ]; then
  echo "Expected $DMG but it wasn't produced." >&2
  exit 1
fi

# Refuse to publish something Gatekeeper would still block. Without this the
# cask installs an app that greets every user with a security warning.
echo "==> Confirming the ticket is stapled…"
xcrun stapler validate "$DMG"

echo "==> Tagging v$VERSION …"
git tag -f "v$VERSION"
git push origin main --tags

echo "==> Creating the GitHub release…"
gh release create "v$VERSION" "$DMG" \
  --repo "$REPO" \
  --title "Claude Launcher $VERSION" \
  --generate-notes \
  || gh release upload "v$VERSION" "$DMG" --repo "$REPO" --clobber

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "==> DMG sha256: $SHA"

echo "==> Updating the Homebrew cask…"
if [ ! -d "$TAP_DIR" ]; then
  git clone "https://github.com/$TAP_REPO.git" "$TAP_DIR"
fi
mkdir -p "$TAP_DIR/Casks"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__SHA256__/$SHA/g" \
    Casks/claude-launcher.rb.template > "$TAP_DIR/Casks/claude-launcher.rb"

git -C "$TAP_DIR" add Casks/claude-launcher.rb
git -C "$TAP_DIR" commit -m "claude-launcher $VERSION" || echo "(cask unchanged)"
git -C "$TAP_DIR" push

echo
echo "==> Published. Install with:"
echo "      brew install --cask $TAP_REPO/claude-launcher"
