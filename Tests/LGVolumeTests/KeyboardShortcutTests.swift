import AppKit
import XCTest
@testable import LGVolume

final class KeyboardShortcutTests: XCTestCase {
    func testCombinedRegistrationStatusIncludesVolumeAndHDMIHotKeys() {
        XCTAssertEqual(
            KeyboardVolumeMonitor.combinedRegistrationStates(
                volume: [true, false, true],
                hdmi: [true, true, false, true]
            ),
            [true, false, true, true, true, false, true]
        )
    }

    func testDefaultHDMIShortcutsAreDistinctAndRoundTrip() throws {
        let shortcuts = try (1...4).map { index in
            try XCTUnwrap(KeyboardShortcut.defaultHDMIShortcut(index: index))
        }

        XCTAssertEqual(Set(shortcuts.map(\.keyCode)).count, 4)
        for shortcut in shortcuts {
            XCTAssertEqual(KeyboardShortcut(storageValue: shortcut.storageValue), shortcut)
        }
    }

    func testRejectsReservedVolumeShortcutFromStorage() {
        let reserved = "109|\(NSEvent.ModifierFlags.command.rawValue)|⌘F10"
        XCTAssertNil(KeyboardShortcut(storageValue: reserved))
    }

    func testRejectsUnmodifiedOrdinaryKeyFromStorage() {
        XCTAssertNil(KeyboardShortcut(storageValue: "0|0|A"))
        XCTAssertNil(KeyboardShortcut(storageValue: "0|0|F1"))
    }

    func testDisplayContainingSeparatorRoundTrips() {
        let shortcut = KeyboardShortcut(keyCode: 42, modifiers: [.control, .option, .shift, .command], display: "⌃⌥⇧⌘|")
        XCTAssertEqual(KeyboardShortcut(storageValue: shortcut.storageValue), shortcut)
    }

    @MainActor
    func testRecorderIgnoresKeyEquivalentsUnlessFocused() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        let recorder = ShortcutRecorderField(frame: NSRect(x: 0, y: 40, width: 200, height: 24))
        window.contentView?.addSubview(other)
        window.contentView?.addSubview(recorder)
        window.makeFirstResponder(other)

        let commandW = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "w",
            charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13
        ))
        XCTAssertFalse(recorder.performKeyEquivalent(with: commandW))
        XCTAssertNil(recorder.shortcut)
        XCTAssertFalse(recorder.isEditable)

        window.makeFirstResponder(recorder)
        XCTAssertTrue(window.firstResponder === recorder)
        XCTAssertTrue(recorder.performKeyEquivalent(with: commandW))
        XCTAssertEqual(recorder.shortcut?.display, "⌘W")
    }
}
