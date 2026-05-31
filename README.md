# LGVolume

LGVolume controls LG webOS TV volume and adds HDMI input switching.

Behavior:

- Click the menu bar icon to show a macOS-style frosted glass control panel.
- The control panel shows volume percentage, mute, volume up/down, HDMI1-HDMI4, Settings, and Quit.
- Press F10 to toggle mute, F11 to reduce volume, and F12 to increase volume. The app listens globally by default, including macOS media-key volume events.
- Use the 2x2 HDMI buttons to switch HDMI1, HDMI2, HDMI3, and HDMI4.
- HDMI button names and HDMI global shortcuts are editable in Settings.
- Settings includes a launch-at-login option.
- Settings includes Auto, Light, and Dark appearance modes.
- The menu bar icon changes to a mute symbol when muted.
- The bundle includes a generated app icon.

Notes:

- The Mac and TV must be on the same local network.
- LGVolume rejects non-private IPv4 addresses and only connects to local network ranges such as `192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`, and `169.254.x.x`.
- First pairing requires confirming the LGVolume authorization prompt on the TV.
- Global shortcut capture may require macOS System Settings -> Privacy & Security -> Accessibility permission for LGVolume. The app asks for this permission on launch.
- Some LG webOS versions use different input IDs. This version sends `HDMI_1`, `HDMI_2`, `HDMI_3`, and `HDMI_4` through `ssap://tv/switchInput`.

Build:

```bash
make build
```

The app bundle is created at:

```text
dist/LGVolume.app
```
