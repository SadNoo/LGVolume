import CoreAudio
import XCTest
@testable import LGVolume

final class TVPowerOffRuleTests: XCTestCase {
    func testLockOnlyCountsAfterTheTVHeldTheMacInputForAMinute() {
        let now = Date()
        XCTAssertFalse(TVSleepPolicy.macInputIsStable(since: nil, now: now), "TV not on the Mac input")
        XCTAssertFalse(TVSleepPolicy.macInputIsStable(since: now.addingTimeInterval(-5), now: now), "just switched back from Switch 2")
        XCTAssertFalse(TVSleepPolicy.macInputIsStable(since: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(TVSleepPolicy.macInputIsStable(since: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(TVSleepPolicy.macInputIsStable(since: now.addingTimeInterval(-3600), now: now))
    }

    func testDeviceKindDefaultsToAutomatic() {
        let defaults = UserDefaults(suiteName: "LGVolumeDeviceKindTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())
        XCTAssertEqual(settings.deviceKindMode, .auto)
        settings.deviceKindMode = .monitor
        XCTAssertEqual(settings.deviceKindMode, .monitor)
    }
}

final class DeviceKindDetectorTests: XCTestCase {
    private func json(_ displays: [[String: String]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["SPDisplaysDataType": [["spdisplays_ndrvs": displays]]])
    }

    func testLGTelevisionIsDetectedAsTV() {
        let data = json([[
            "_name": "LG TV SSCR2",
            "_spdisplays_display-vendor-id": "1e6d",
            "spdisplays_television": "spdisplays_yes"
        ]])
        XCTAssertEqual(DeviceKindDetector.kind(fromSystemProfilerJSON: data), .tv)
    }

    func testLGMonitorWithoutTelevisionFlagIsMonitor() {
        let data = json([["_name": "LG ULTRAFINE", "_spdisplays_display-vendor-id": "1e6d"]])
        XCTAssertEqual(DeviceKindDetector.kind(fromSystemProfilerJSON: data), .monitor)
    }

    func testPrefersTheLGDisplayWhenSeveralAreConnected() {
        let data = json([
            ["_name": "Studio Display", "_spdisplays_display-vendor-id": "610"],
            ["_name": "LG TV", "_spdisplays_display-vendor-id": "1e6d", "spdisplays_television": "spdisplays_yes"]
        ])
        XCTAssertEqual(DeviceKindDetector.kind(fromSystemProfilerJSON: data), .tv)
    }

    func testUnknownWhenItCannotTell() {
        XCTAssertNil(DeviceKindDetector.kind(fromSystemProfilerJSON: Data("not json".utf8)))
        let twoOthers = json([
            ["_name": "A", "_spdisplays_display-vendor-id": "610"],
            ["_name": "B", "_spdisplays_display-vendor-id": "4c2d"]
        ])
        XCTAssertNil(DeviceKindDetector.kind(fromSystemProfilerJSON: twoOthers))
    }
}

@MainActor
final class DisplayOffStandbyGateTests: XCTestCase {
    /// Collects scheduled actions so the test decides when time passes.
    private final class ManualClock {
        var pending: [(action: @MainActor () -> Void, cancelled: Bool)] = []

        func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            pending.append((action, false))
            let index = pending.count - 1
            return { [weak self] in self?.pending[index].cancelled = true }
        }

        @MainActor
        func elapse() {
            let due = pending
            pending.removeAll()
            for item in due where !item.cancelled {
                item.action()
            }
        }
    }

    private func makeGate(_ clock: ManualClock, fired: @escaping () -> Void) -> DisplayOffStandbyGate {
        DisplayOffStandbyGate(delay: 60, schedule: { clock.schedule($0, $1) }, onElapsed: fired)
    }

    func testPictureOffForTheWholeMinuteFiresOnce() {
        let clock = ManualClock()
        var fired = 0
        let gate = makeGate(clock) { fired += 1 }
        gate.displaysDidSleep()
        gate.displaysDidSleep()
        clock.elapse()
        XCTAssertEqual(fired, 1)
    }

    func testInputSwitchBlipThatComesBackDoesNothing() {
        let clock = ManualClock()
        var fired = 0
        let gate = makeGate(clock) { fired += 1 }
        gate.displaysDidSleep()
        gate.displaysDidWake()
        clock.elapse()
        XCTAssertEqual(fired, 0)
    }

    func testTVChangingInputWhileOffDoesNothing() {
        let clock = ManualClock()
        var fired = 0
        let gate = makeGate(clock) { fired += 1 }
        gate.displaysDidSleep()
        gate.tvInputChanged()
        clock.elapse()
        XCTAssertEqual(fired, 0)
        gate.displaysDidSleep()
        clock.elapse()
        XCTAssertEqual(fired, 0, "still the same off period; wake first to start again")
    }
}

final class VolumeKeysAndStandbyActionTests: XCTestCase {
    func testTVAudioIsRecognisedByTransportOrName() {
        XCTAssertTrue(AudioOutputMonitor.isTVOutput(name: "LG TV SSCR2", transport: kAudioDeviceTransportTypeDisplayPort))
        XCTAssertTrue(AudioOutputMonitor.isTVOutput(name: "Television", transport: kAudioDeviceTransportTypeHDMI))
        XCTAssertTrue(AudioOutputMonitor.isTVOutput(name: "LG TV", transport: 0))
        XCTAssertFalse(AudioOutputMonitor.isTVOutput(name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth))
        XCTAssertFalse(AudioOutputMonitor.isTVOutput(name: "Mac mini Speakers", transport: kAudioDeviceTransportTypeBuiltIn))
        XCTAssertFalse(AudioOutputMonitor.isTVOutput(name: "USB Audio DAC", transport: kAudioDeviceTransportTypeUSB))
    }

    func testDefaultsKeepCurrentBehaviourSafe() {
        let defaults = UserDefaults(suiteName: "LGVolumeKeysTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())
        XCTAssertTrue(settings.volumeKeysOnlyForTVAudio)
        XCTAssertEqual(settings.standbyAction, .powerOff)
        settings.standbyAction = .screenOff
        XCTAssertEqual(settings.standbyAction, .screenOff)
    }
}
