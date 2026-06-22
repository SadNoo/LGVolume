import AppKit
import XCTest
@testable import LGVolume

final class KeyboardShortcutTests: XCTestCase {
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
}
