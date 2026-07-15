import XCTest
@testable import LGVolume

final class WebOSClientTests: XCTestCase {
    func testParsesMuteStatusVariants() {
        XCTAssertEqual(WebOSResponseParser.muteStatus(["mute": true]), true)
        XCTAssertEqual(WebOSResponseParser.muteStatus(["muted": false]), false)
        XCTAssertEqual(WebOSResponseParser.muteStatus(["volumeStatus": ["muteStatus": true]]), true)
        XCTAssertNil(WebOSResponseParser.muteStatus(["volume": 42]))
    }

    func testParsesNestedVolumeStatus() throws {
        let status = try XCTUnwrap(WebOSResponseParser.volumeStatus([
            "volumeStatus": ["volume": 42, "muted": true]
        ]))

        XCTAssertEqual(status.volume, 42)
        XCTAssertEqual(status.muted, true)
    }

    func testParsesStringVolumeAndClampsRange() throws {
        let high = try XCTUnwrap(WebOSResponseParser.volumeStatus(["volume": "120", "mute": false]))
        let low = try XCTUnwrap(WebOSResponseParser.volumeStatus(["volume": -5]))

        XCTAssertEqual(high.volume, 100)
        XCTAssertEqual(high.muted, false)
        XCTAssertEqual(low.volume, 0)
        XCTAssertNil(low.muted)
    }

    func testParsesFractionalVolumeByRoundingToNearestInteger() throws {
        let status = try XCTUnwrap(WebOSResponseParser.volumeStatus(["volume": 42.6]))

        XCTAssertEqual(status.volume, 43)
    }

    func testRejectsVolumeResponseWithoutVolume() {
        XCTAssertNil(WebOSResponseParser.volumeStatus(["muted": false]))
    }

    func testParsesExternalInputsAndHDMIIndexes() throws {
        let inputs = WebOSResponseParser.externalInputs([
            "devices": [
                ["id": "HDMI_1", "label": "Mac mini", "appId": "com.webos.app.hdmi1", "port": 1, "connected": true],
                ["id": "AV_1", "label": "AV"]
            ]
        ])

        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs[0].hdmiIndex, 1)
        XCTAssertEqual(inputs[0].label, "Mac mini")
        XCTAssertTrue(try XCTUnwrap(inputs[0].connected))
        XCTAssertNil(inputs[1].hdmiIndex)
    }

    func testParsesNestedSoundOutput() {
        XCTAssertEqual(WebOSResponseParser.soundOutput(["soundOutput": "external_arc"]), "external_arc")
        XCTAssertEqual(
            WebOSResponseParser.soundOutput(["soundOutputStatus": ["soundOutput": "tv_speaker"]]),
            "tv_speaker"
        )
    }
}
