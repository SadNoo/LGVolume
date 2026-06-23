import XCTest
@testable import LGVolume

@MainActor
final class WebOSIntegrationTests: XCTestCase {
    func testSavedTVAcceptsVolumeAndHDMIRequests() async throws {
        guard ProcessInfo.processInfo.environment["LGVOLUME_RUN_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set LGVOLUME_RUN_INTEGRATION_TESTS=1 to test against the saved LG TV.")
        }

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "local.codex.lgvolume"))
        let ip = defaults.string(forKey: "tvIP") ?? ""
        let clientKey = defaults.string(forKey: "clientKey") ?? ""
        try XCTSkipIf(ip.isEmpty, "No saved LG TV IP.")
        try XCTSkipIf(clientKey.isEmpty, "No saved LG TV client key.")

        let client = WebOSClient()
        defer { client.disconnect() }

        let connectResult = await connect(client, ip: ip, clientKey: clientKey)
        guard case .success = connectResult else {
            return XCTFail("Could not connect to saved TV: \(connectResult)")
        }

        let volumeResult = await getVolume(client)
        guard case .success(let volumeStatus) = volumeResult else {
            return XCTFail("Could not read TV volume: \(volumeResult)")
        }

        let setVolumeResult = await setVolume(client, volume: volumeStatus.volume)
        guard case .success = setVolumeResult else {
            return XCTFail("Could not set TV volume to current value: \(setVolumeResult)")
        }

        let hdmiResult = await getCurrentHDMI(client)
        guard case .success(let currentHDMI) = hdmiResult else {
            return XCTFail("Could not read current HDMI input: \(hdmiResult)")
        }
        guard let currentHDMI else {
            throw XCTSkip("Current foreground input is not HDMI; skipping non-disruptive HDMI switch.")
        }

        let switchResult = await switchHDMI(client, index: currentHDMI)
        guard case .success = switchResult else {
            return XCTFail("Could not switch back to current HDMI \(currentHDMI): \(switchResult)")
        }
    }

    private func connect(_ client: WebOSClient, ip: String, clientKey: String) async -> LGResult<String> {
        await withCheckedContinuation { continuation in
            client.connect(ip: ip, clientKey: clientKey, forcePairing: false) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func getVolume(_ client: WebOSClient) async -> LGResult<TVVolumeStatus> {
        await withCheckedContinuation { continuation in
            client.getVolume { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func setVolume(_ client: WebOSClient, volume: Int) async -> LGResult<Void> {
        await withCheckedContinuation { continuation in
            client.setVolume(volume) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func getCurrentHDMI(_ client: WebOSClient) async -> LGResult<Int?> {
        await withCheckedContinuation { continuation in
            client.getCurrentHDMI { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func switchHDMI(_ client: WebOSClient, index: Int) async -> LGResult<Void> {
        await withCheckedContinuation { continuation in
            client.switchHDMI(index) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
