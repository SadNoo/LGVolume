import XCTest
@testable import LGVolume

final class PairingTokenStoreTests: XCTestCase {
    func testStoresTokenWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LGVolumeTokenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilePairingTokenStore(directoryURL: directory)

        XCTAssertTrue(store.save("paired-token"))
        XCTAssertEqual(store.read(), "paired-token")

        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("webos-pairing-token").path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        store.clear()
        XCTAssertTrue(store.read().isEmpty)
    }

    func testMigratesLegacyPreferencesWithoutKeychainAccess() throws {
        let suiteName = "local.codex.lgvolume.token-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-token", forKey: "clientKey")
        let store = MemoryPairingTokenStore()

        let settings = AppSettings(defaults: defaults, tokenStore: store)

        XCTAssertEqual(settings.clientKey, "legacy-token")
        XCTAssertNil(defaults.string(forKey: "clientKey"))
    }
}
