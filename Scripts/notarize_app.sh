#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="dist/LGVolume.app"
ARCHIVE="dist/LGVolume-notarization.zip"

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
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
  xcrun notarytool submit "$ARCHIVE" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
else
  echo "Set NOTARY_PROFILE, or NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER." >&2
  exit 1
fi
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"

echo "Notarized $APP_BUNDLE"
