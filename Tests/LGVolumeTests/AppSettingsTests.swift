import Foundation
import XCTest
@testable import LGVolume

final class AppSettingsTests: XCTestCase {
    func testDisabledShortcutDoesNotRestoreDefault() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, clientKeyStorage: MemoryClientKeyStorage())

        XCTAssertNotNil(settings.hdmiShortcut(1))
        settings.setHDMIShortcut(nil, index: 1)
        XCTAssertNil(settings.hdmiShortcut(1))

        settings.resetHDMIShortcuts()
        XCTAssertNotNil(settings.hdmiShortcut(1))
    }

    func testMigratesLegacyClientKeyOutOfDefaults() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-key", forKey: "clientKey")

        let storage = MemoryClientKeyStorage()
        let settings = AppSettings(defaults: defaults, clientKeyStorage: storage)

        XCTAssertEqual(settings.clientKey, "legacy-key")
        XCTAssertNil(defaults.string(forKey: "clientKey"))
    }

    func testSecureConnectionOnlyDefaultsToFalseAndPersists() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, clientKeyStorage: MemoryClientKeyStorage())

        XCTAssertFalse(settings.secureConnectionOnly)
        settings.secureConnectionOnly = true
        XCTAssertTrue(settings.secureConnectionOnly)
    }
}

private final class MemoryClientKeyStorage: ClientKeyStorage {
    private var value = ""

    func read() -> String {
        value
    }

    func save(_ value: String) -> Bool {
        self.value = value
        return true
    }

    func clear() {
        value = ""
    }
}
