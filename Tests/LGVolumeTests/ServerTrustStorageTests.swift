import XCTest
@testable import LGVolume

final class ServerTrustStorageTests: XCTestCase {
    func testStoresFingerprintsPerTVWithoutKeychainAccess() throws {
        let suiteName = "local.codex.lgvolume.trust-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = DefaultsServerTrustStorage(defaults: defaults)

        XCTAssertTrue(storage.saveFingerprint("first", for: "192.168.1.20"))
        XCTAssertTrue(storage.saveFingerprint("second", for: "192.168.1.21"))
        XCTAssertEqual(storage.fingerprint(for: "192.168.1.20"), "first")
        XCTAssertEqual(storage.fingerprint(for: "192.168.1.21"), "second")

        storage.clearFingerprint(for: "192.168.1.20")
        XCTAssertEqual(storage.fingerprint(for: "192.168.1.20"), "")
        XCTAssertEqual(storage.fingerprint(for: "192.168.1.21"), "second")
    }
}
