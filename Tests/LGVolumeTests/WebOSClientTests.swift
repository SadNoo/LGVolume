import XCTest
@testable import LGVolume

final class WebOSClientTests: XCTestCase {
    func testParsesNestedVolumeStatus() throws {
        let status = try XCTUnwrap(WebOSClient.parseVolumeStatus([
            "volumeStatus": ["volume": 42, "muted": true]
        ]))

        XCTAssertEqual(status.volume, 42)
        XCTAssertTrue(status.muted)
    }

    func testParsesStringVolumeAndClampsRange() throws {
        let high = try XCTUnwrap(WebOSClient.parseVolumeStatus(["volume": "120", "mute": false]))
        let low = try XCTUnwrap(WebOSClient.parseVolumeStatus(["volume": -5]))

        XCTAssertEqual(high.volume, 100)
        XCTAssertFalse(high.muted)
        XCTAssertEqual(low.volume, 0)
    }

    func testRejectsVolumeResponseWithoutVolume() {
        XCTAssertNil(WebOSClient.parseVolumeStatus(["muted": false]))
    }
}
