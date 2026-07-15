import XCTest
@testable import LGVolume

final class DiagnosticsLoggerTests: XCTestCase {
    func testRedactsIPAndPairingTokens() {
        let source = #"connect 192.168.1.44 client-key=secret-value {"client-key":"other-secret"}"#
        let redacted = DiagnosticsLogger.redacted(source)

        XCTAssertFalse(redacted.contains("192.168.1.44"))
        XCTAssertFalse(redacted.contains("secret-value"))
        XCTAssertFalse(redacted.contains("other-secret"))
        XCTAssertTrue(redacted.contains("<ip>"))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    func testWritesOwnerOnlyLog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LGVolumeLogTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticsLogger(directoryURL: directory, maximumBytes: 1024)

        logger.log("network", "connected to 192.168.1.44")

        let text = try String(contentsOf: logger.logURL, encoding: .utf8)
        XCTAssertFalse(text.contains("192.168.1.44"))
        let attributes = try FileManager.default.attributesOfItem(atPath: logger.logURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
