# LGVolume

LGVolume controls LG webOS TV volume and adds HDMI input switching.

Behavior:

- Left click the menu bar icon to show the macOS-style volume panel.
- Right click the menu bar icon to show Settings and Quit.
- Drag the volume bar to adjust TV volume.
- Click the left speaker icon to toggle mute.
- Press F10 to toggle mute, F11 to reduce volume, and F12 to increase volume. The app listens globally by default, including macOS media-key volume events.
- Use the 2x2 HDMI buttons under the volume track to switch HDMI1, HDMI2, HDMI3, and HDMI4.
- HDMI button names are editable in Settings.
- Settings includes Auto, Light, and Dark appearance modes.
- The menu bar icon changes to a mute symbol when muted.
- The bundle includes a generated app icon.

Notes:

- The Mac and TV must be on the same local network.
- First pairing requires confirming the LGVolume authorization prompt on the TV.
- F10/F11/F12 global capture may require macOS System Settings -> Privacy & Security -> Accessibility permission for LGVolume. The app asks for this permission on launch.
- Some LG webOS versions use different input IDs. This version sends `HDMI_1`, `HDMI_2`, `HDMI_3`, and `HDMI_4` through `ssap://tv/switchInput`.

Build:

```bash
make build
```

The app bundle is created at:

```text
dist/LGVolume.app
```
