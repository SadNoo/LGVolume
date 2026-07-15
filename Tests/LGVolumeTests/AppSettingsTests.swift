import Foundation
import XCTest
@testable import LGVolume

final class AppSettingsTests: XCTestCase {
    func testDisabledShortcutDoesNotRestoreDefault() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())

        XCTAssertNotNil(settings.hdmiShortcut(1))
        settings.setHDMIShortcut(nil, index: 1)
        XCTAssertNil(settings.hdmiShortcut(1))

        settings.resetHDMIShortcuts()
        XCTAssertNotNil(settings.hdmiShortcut(1))
    }

    func testClientKeyPersistsInTokenStoreAndCanBeCleared() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = MemoryPairingTokenStore()
        let settings = AppSettings(defaults: defaults, tokenStore: tokenStore)
        settings.saveClientKey("paired-key")

        XCTAssertEqual(settings.clientKey, "paired-key")
        XCTAssertEqual(tokenStore.token, "paired-key")
        XCTAssertNil(defaults.string(forKey: "clientKey"))

        settings.clearClientKey()
        XCTAssertTrue(settings.clientKey.isEmpty)
        XCTAssertNil(defaults.string(forKey: "clientKey"))
    }

    func testSecureConnectionOnlyDefaultsToFalseAndPersists() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())

        XCTAssertFalse(settings.secureConnectionOnly)
        settings.secureConnectionOnly = true
        XCTAssertTrue(settings.secureConnectionOnly)
    }

    func testTVInputNamePreferenceDefaultsToFalseAndPersists() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())

        XCTAssertFalse(settings.useTVInputNames)
        settings.useTVInputNames = true
        XCTAssertTrue(settings.useTVInputNames)
    }

}
