#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(tr -d '[:space:]' < BUILD_NUMBER)"
RELEASE_DIR="dist/release/v$VERSION"
APP_BUNDLE="dist/LGVolume.app"
ZIP_PATH="$RELEASE_DIR/LGVolume-v$VERSION-arm64.zip"
DMG_PATH="$RELEASE_DIR/LGVolume-v$VERSION-arm64.dmg"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid VERSION: $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid BUILD_NUMBER: $BUILD_NUMBER" >&2
  exit 1
fi

make test
make build

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
hdiutil create -quiet -volname "LGVolume $VERSION" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || true

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > SHA256SUMS.txt
)

cat > "$RELEASE_DIR/RELEASE.txt" <<EOF
LGVolume $VERSION (build $BUILD_NUMBER)
Architecture: Apple Silicon (arm64)
Minimum macOS: 14.0

The application uses only the local network at runtime. Pairing tokens are stored
in Application Support with owner-only permissions and never in macOS Keychain.
EOF

echo "Release artifacts created in $RELEASE_DIR"

if [[ "${PUBLISH_GITHUB_RELEASE:-0}" == "1" ]]; then
  command -v gh >/dev/null || { echo "gh is required to publish a GitHub Release." >&2; exit 1; }
  gh release create "v$VERSION" "$ZIP_PATH" "$DMG_PATH" "$RELEASE_DIR/SHA256SUMS.txt" \
    --title "LGVolume v$VERSION" --generate-notes
fi
