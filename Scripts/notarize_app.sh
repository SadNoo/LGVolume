#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="dist/LGVolume.app"
ARCHIVE="dist/LGVolume-notarization.zip"

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile." >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing $APP_BUNDLE. Run make build with DEVELOPER_ID_APPLICATION first." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
if [[ "$SIGNATURE_INFO" != *"Authority=Developer ID Application:"* ]]; then
  echo "The app must be signed with a Developer ID Application certificate before notarization." >&2
  exit 1
fi
ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"

echo "Notarized $APP_BUNDLE"
