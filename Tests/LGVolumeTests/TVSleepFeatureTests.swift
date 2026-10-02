import XCTest
@testable import LGVolume

final class EDIDParserTests: XCTestCase {
    func testReadsLGInputPortFromHDMIPhysicalAddress() {
        for port in 1...4 {
            let edid = Self.makeEDID(manufacturer: (0x1E, 0x6D), physicalAddress: (UInt8(port << 4), 0x00))
            XCTAssertEqual(EDIDParser.manufacturerID(from: edid), "GSM")
            XCTAssertEqual(EDIDParser.physicalAddress(from: edid), [port, 0, 0, 0])
            XCTAssertEqual(EDIDParser.lgTVInputPort(from: edid), port)
        }
    }

    func testSourceBehindReceiverStillMapsToTVInput() {
        let edid = Self.makeEDID(manufacturer: (0x1E, 0x6D), physicalAddress: (0x21, 0x00))
        XCTAssertEqual(EDIDParser.lgTVInputPort(from: edid), 2)
    }

    func testIgnoresNonLGDisplaysAndMissingVendorBlock() {
        let dell = Self.makeEDID(manufacturer: (0x10, 0xAC), physicalAddress: (0x10, 0x00))
        XCTAssertNil(EDIDParser.lgTVInputPort(from: dell))

        let noVSDB = Self.makeEDID(manufacturer: (0x1E, 0x6D), physicalAddress: nil)
        XCTAssertNil(EDIDParser.lgTVInputPort(from: noVSDB))
        XCTAssertNil(EDIDParser.lgTVInputPort(from: Data([0, 1, 2])))
    }

    /// A minimal EDID: a base block plus one CTA-861 extension with an optional HDMI VSDB.
    static func makeEDID(manufacturer: (UInt8, UInt8), physicalAddress: (UInt8, UInt8)?) -> Data {
        var base = [UInt8](repeating: 0, count: 128)
        base.replaceSubrange(0..<8, with: [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
        base[8] = manufacturer.0
        base[9] = manufacturer.1
        base[126] = 1

        var cta = [UInt8](repeating: 0, count: 128)
        cta[0] = 0x02
        cta[1] = 0x03
        var blocks: [UInt8] = [0x42, 0x10, 0x04] // video data block, two VICs
        if let address = physicalAddress {
            blocks += [0x65, 0x03, 0x0C, 0x00, address.0, address.1]
        }
        cta[2] = UInt8(4 + blocks.count)
        cta.replaceSubrange(4..<(4 + blocks.count), with: blocks)
        return Data(base + cta)
    }
}

final class TVSleepPolicyTests: XCTestCase {
    private let inputs = [
        TVExternalInput(id: "HDMI_1", label: "Mac mini", appID: "com.webos.app.hdmi1", port: 1, connected: true),
        TVExternalInput(id: "HDMI_2", label: "Switch 2", appID: "com.webos.app.hdmi2", port: 2, connected: true)
    ]

    func testTurnsOffOnlyWhileTVShowsTheMacInput() {
        XCTAssertEqual(
            TVSleepPolicy.decide(enabled: true, macPort: 1, foregroundAppID: "com.webos.app.hdmi1", inputs: inputs),
            .turnOff
        )
    }

    func testNeverTurnsOffWhileAnotherHDMIInputIsShown() {
        let decision = TVSleepPolicy.decide(
            enabled: true, macPort: 1, foregroundAppID: "com.webos.app.hdmi2", inputs: inputs
        )
        XCTAssertNotEqual(decision, .turnOff)
    }

    func testAfterSwitchingBackFromConsoleTheMacInputIsRecognisedAgain() {
        var foreground = "com.webos.app.hdmi2"
        XCTAssertNotEqual(TVSleepPolicy.decide(enabled: true, macPort: 1, foregroundAppID: foreground, inputs: inputs), .turnOff)
        foreground = "com.webos.app.hdmi1"
        XCTAssertEqual(TVSleepPolicy.decide(enabled: true, macPort: 1, foregroundAppID: foreground, inputs: inputs), .turnOff)
    }

    func testLeavesTVAloneWhenAnythingIsUncertain() {
        XCTAssertNotEqual(TVSleepPolicy.decide(enabled: false, macPort: 1, foregroundAppID: "com.webos.app.hdmi1", inputs: inputs), .turnOff)
        XCTAssertNotEqual(TVSleepPolicy.decide(enabled: true, macPort: nil, foregroundAppID: "com.webos.app.hdmi1", inputs: inputs), .turnOff)
        XCTAssertNotEqual(TVSleepPolicy.decide(enabled: true, macPort: 1, foregroundAppID: nil, inputs: inputs), .turnOff)
        XCTAssertNotEqual(TVSleepPolicy.decide(enabled: true, macPort: 1, foregroundAppID: "", inputs: inputs), .turnOff)
        XCTAssertNotEqual(TVSleepPolicy.decide(enabled: true, macPort: 1, foregroundAppID: "netflix", inputs: inputs), .turnOff)
        XCTAssertNotEqual(TVSleepPolicy.decide(enabled: true, macPort: 1, foregroundAppID: "com.webos.app.livetv", inputs: inputs), .turnOff)
    }

    func testRegistrationRequestsPowerOnlyWhenAsked() {
        let plain = WebOSRegistration.payload(forcePairing: false)
        let withPower = WebOSRegistration.payload(forcePairing: true, includePowerControl: true)
        XCTAssertFalse(Self.permissions(plain).contains("CONTROL_POWER"))
        XCTAssertTrue(Self.permissions(withPower).contains("CONTROL_POWER"))
    }

    func testClearingPairingAlsoForgetsPowerGrant() {
        let defaults = UserDefaults(suiteName: "LGVolumeSleepTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())
        settings.pairingGrantsPower = true
        settings.clearClientKey()
        XCTAssertFalse(settings.pairingGrantsPower)

        settings.macHDMIPortOverride = 7
        XCTAssertEqual(settings.macHDMIPortOverride, 0)
        XCTAssertNil(settings.lastDetectedMacHDMIPort)
    }

    private static func permissions(_ payload: [String: Any]) -> [String] {
        (payload["manifest"] as? [String: Any])?["permissions"] as? [String] ?? []
    }
}
