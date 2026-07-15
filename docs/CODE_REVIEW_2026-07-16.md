# LGVolume v0.2.0 Review

## Implemented improvements

1. Volume commands are read back from the TV. A mismatched or rejected command retries once with the alternate absolute/stepped API.
2. Local diagnostics record request URIs, state transitions, retries, and failures. IPv4 addresses and pairing tokens are redacted; logs rotate at 512 KiB.
3. `make tv-test` performs an opt-in real-TV test and restores volume and mute state. HDMI is switched only to the already active input.
4. Response parsing, registration data, token storage, diagnostics, and volume execution are separated from the WebSocket and coordinator code.
5. The menu includes the actual sound-output ID returned by the TV and removes an option only after an explicit unsupported/invalid response.
6. Menu width adapts from 184 to 240 points for long custom names, with hover help on HDMI buttons.
7. The pairing token is stored outside preferences in Application Support with a `0700` directory and `0600` file. No runtime Keychain API is linked.
8. `VERSION` and `BUILD_NUMBER` drive the app bundle and release filenames. `make release` produces arm64 ZIP/DMG artifacts and SHA-256 checksums.
9. Historical binary installers were removed from the source tree. New installers belong in GitHub Releases.

## Verification gates

- Unit, parser, persistence, redaction, visual, and volume-command tests must pass.
- The opt-in real-TV integration test must pass before publishing.
- `git diff --check`, Info.plist validation, code-signature validation, architecture inspection, and checksum verification must pass.
- Source and untracked files are scanned for the user's TV IP, GitHub tokens, cloud credentials, private keys, and password assignments.
- The final Mach-O undefined-symbol list must contain no `SecItem*` or Keychain symbol.

## Distribution note

The default local build is ad-hoc signed. Release automation supports Developer ID signing and Apple notarization with an App Store Connect API key, but a publicly trusted build requires the project owner's Apple Developer credentials.
