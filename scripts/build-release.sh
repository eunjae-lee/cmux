#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA="/tmp/cmux-release"

cd "$PROJECT_DIR"

# Get version from Xcode project
VERSION=$(grep 'MARKETING_VERSION' GhosttyTabs.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;.*//')
echo "==> Version: $VERSION"

echo "==> Building release..."
CMUX_SKIP_ZIG_BUILD=1 xcodebuild \
  -project GhosttyTabs.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build 2>&1 | tail -3

APP_PATH="$DERIVED_DATA/Build/Products/Release/cmux.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: cmux.app not found at $APP_PATH"
  exit 1
fi

echo "==> Zipping..."
ZIP_PATH="/tmp/cmux-fork.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
echo "==> Zip: $ZIP_PATH ($SIZE)"

# Upload to GitHub release
TAG="v${VERSION}-fork"
echo "==> Uploading to GitHub release $TAG..."

# Delete existing release if any
gh release delete "$TAG" --repo eunjae-lee/cmux --yes 2>/dev/null || true

gh release create "$TAG" \
  --repo eunjae-lee/cmux \
  --title "cmux $VERSION (fork)" \
  --notes "Fork build with workspace provider support." \
  "$ZIP_PATH#cmux-fork.zip"

echo "==> Release: https://github.com/eunjae-lee/cmux/releases/tag/$TAG"

# Update homebrew tap
SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
echo "==> SHA256: $SHA256"

TAP_DIR="$HOME/workspace/homebrew-cmux"
if [ -d "$TAP_DIR" ]; then
  cat > "$TAP_DIR/Casks/cmux-fork.rb" << CASK
cask "cmux-fork" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/eunjae-lee/cmux/releases/download/v#{version}-fork/cmux-fork.zip"
  name "cmux (fork)"
  desc "Terminal workspace manager with provider extensions"
  homepage "https://github.com/eunjae-lee/cmux"

  app "cmux.app"

  zap trash: [
    "~/Library/Application Support/cmux",
    "~/.config/cmux",
  ]
end
CASK
  cd "$TAP_DIR" && git add -A && git commit -m "update cmux-fork to $VERSION" && git push
  echo "==> Homebrew tap updated"
else
  echo "==> Homebrew tap not found at $TAP_DIR (create it first)"
fi

echo "==> Done!"
