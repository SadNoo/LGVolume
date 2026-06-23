# LGVolume v0.1.5

Apple Silicon only. Requires macOS 14 or later.

## Changes

- Updated keyboard volume shortcuts to 5% steps.
- Rounded fractional LG webOS volume values to the nearest integer before displaying or adjusting volume.
- Removed the menu panel volume slider to avoid double-track rendering; volume is now shown as a clear percentage and controlled by F11/F12.
- Reworked the settings tabs into a compact native macOS segmented control.
- Replaced custom-drawn settings/menu UI pieces with native controls where possible.
- Restored robust F10/F11/F12 handling for both media-key and standard function-key events.
- Added optional real-TV integration coverage while keeping normal tests offline and local-only.
- Refreshed the README with bilingual usage, migration, permission, and troubleshooting notes.

## Files

- `LGVolume-v0.1.5-arm64.dmg`
- `LGVolume-v0.1.5-arm64.zip`

## SHA256

```text
c690721b7a9baa021007d53ab920583668efa56648303ef00f26322436237ab6  LGVolume-v0.1.5-arm64.dmg
09bf459f5c87167d72b487966a412b19207ae479b7ef2a79b251baf7afddb90f  LGVolume-v0.1.5-arm64.zip
```

## Install

Open the DMG and drag `LGVolume.app` into `/Applications`, or unzip the ZIP archive and move the app manually.

On a new Mac, launch LGVolume, enter the LG TV IP, pair with the TV when prompted, then enable Local Network and keyboard monitoring permissions if macOS asks for them.
