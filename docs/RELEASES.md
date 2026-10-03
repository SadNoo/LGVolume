# Release History

Binary installers are published through GitHub Releases rather than committed to the source tree.

| Version | Summary |
| --- | --- |
| 1.3.0 | Turn the LG TV off with the Mac in TV mode (Touch ID lock, after the TV has shown the Mac input for 60 s; 10 s grace for CEC) or monitor mode (picture off 60 s), device type auto-detection, power-off or screen-off action with fallback, a test button that simulates the decision, and volume keys that control the TV only while the Mac's sound goes to it. |
| 1.1.0 | Mac sleep puts the TV in standby only while it shows the Mac's HDMI input (detected from the EDID), six switchable menu panel styles, AppKit status item, native-step keyboard volume, review fixes, and a packaging fix that ensures the freshly built binary is shipped. |
| 1.0.0 | UI and stability baseline (not published as a release). |
| 0.2.0 | Verified volume commands, real-time state subscriptions, dynamic inputs and audio outputs, owner-only token storage, diagnostics, and release automation. |
| 0.1.6 | Settings and menu-bar refinements. |
| 0.1.0–0.1.5 | Initial webOS volume, mute, HDMI, shortcuts, localization, and packaging work. |

Run `make release` to test, build, package ZIP/DMG files, and create SHA-256 checksums. Set
`PUBLISH_GITHUB_RELEASE=1` to publish the generated artifacts with GitHub CLI after the source commit and tag are pushed.
