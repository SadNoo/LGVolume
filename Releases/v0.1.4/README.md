# LGVolume v0.1.4

Apple Silicon only. Requires macOS 14 or later.

## Changes

- Fixed first-pairing timing so the TV authorization prompt can remain open for up to 90 seconds.
- Restored HDMI switching permissions and added a launcher-based fallback for compatible LG webOS firmware.
- Removed Keychain and Accessibility permission requirements; global shortcuts now use Carbon hot keys.
- Added direct percentage volume control with queued command coalescing and stricter response validation.
- Added current HDMI input synchronization and improved connection-state handling.
- Redesigned the menu panel and settings window with compact, localized sections.
- Added editable and disableable HDMI shortcuts with registration feedback.
- Added Simplified Chinese, English, and Japanese system permission descriptions.
- Refined the app icon and removed the top translucent highlight bar.
- Added automated logic, localization, shortcut, parsing, and visual rendering tests.

## Installation

Download either package below. Move `LGVolume.app` to Applications, launch it, enter the TV's local IP address, and approve LGVolume on the TV when prompted.

If HDMI switching does not work after upgrading from an earlier version, disconnect and pair again so the TV can grant the updated permissions.

## Files

- `LGVolume-v0.1.4-arm64.dmg`
- `LGVolume-v0.1.4-arm64.zip`

## SHA256

```text
4f7bd36c081f9572290fe328b652fcc10f1a834a7b8a2f6a0e104e2e80e14cd6  LGVolume-v0.1.4-arm64.dmg
a54d57a95e1821d5c084268221754ad0e13818c6fdb824f8589d73c1fa473df9  LGVolume-v0.1.4-arm64.zip
```
