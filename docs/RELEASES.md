# Release History

Binary installers are published through GitHub Releases rather than committed to the source tree.

| Version | Summary |
| --- | --- |
| 0.2.0 | Verified volume commands, real-time state subscriptions, dynamic inputs and audio outputs, owner-only token storage, diagnostics, and release automation. |
| 0.1.6 | Settings and menu-bar refinements. |
| 0.1.0–0.1.5 | Initial webOS volume, mute, HDMI, shortcuts, localization, and packaging work. |

Run `make release` to test, build, package ZIP/DMG files, and create SHA-256 checksums. Set
`PUBLISH_GITHUB_RELEASE=1` to publish the generated artifacts with GitHub CLI after the source commit and tag are pushed.
