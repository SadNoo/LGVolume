# LGVolume v0.1.6

Apple Silicon only. Requires macOS 14 or later.

## Changes

- Moved the LG webOS client key from UserDefaults to macOS Keychain, with automatic migration from older versions.
- Fixed Disconnect so it works even if the current Settings IP field contains an invalid unsaved value.
- Added an optional "Use secure connection only (WSS)" preference.
- Reworked Settings into a fixed footer Save layout so controls no longer jump between pages.
- Improved Settings form alignment and HDMI name field alignment.
- Improved menu panel action rows with a fixed icon column so custom HDMI names line up cleanly.
- Updated bilingual README privacy notes to describe Keychain storage and the WSS-only option.

## Files

- `LGVolume-v0.1.6-arm64.dmg`
- `LGVolume-v0.1.6-arm64.zip`

## SHA256

```text
e55d1ae047dcd35c498d45ea9e506de7c3bdc44e3fff7d06ace5950ae7723a7a  LGVolume-v0.1.6-arm64.dmg
d5955aa883411dde9ad0e3754313d00afb4ab73b837f83fb357ecedc0dc1b0bd  LGVolume-v0.1.6-arm64.zip
```

## Install

Open the DMG and drag `LGVolume.app` into `/Applications`, or unzip the ZIP archive and move the app manually.

The app is ad-hoc signed for local distribution. On another Mac, macOS may ask you to allow the first launch in System Settings > Privacy & Security.
