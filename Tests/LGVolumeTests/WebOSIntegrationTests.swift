import XCTest
@testable import LGVolume

@MainActor
final class WebOSIntegrationTests: XCTestCase {
    func testSavedTVAcceptsRealtimeAudioInputAndOutputRequests() async throws {
        guard ProcessInfo.processInfo.environment["LGVOLUME_RUN_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set LGVOLUME_RUN_INTEGRATION_TESTS=1 to test against the saved LG TV.")
        }

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "local.codex.lgvolume"))
        let settings = AppSettings(defaults: defaults)
        let environment = ProcessInfo.processInfo.environment
        let ip = environment["LGVOLUME_TV_IP"] ?? settings.tvIP
        let clientKey = environment["LGVOLUME_CLIENT_KEY"] ?? settings.clientKey
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

        let direction = volumeStatus.volume < 100 ? 1 : -1
        let testVolume = volumeStatus.volume + direction
        let executor = VolumeCommandExecutor(controller: client, verificationFailure: { "TV did not apply volume" })
        let changedVolumeResult = await executeVolume(executor, target: testVolume, current: volumeStatus.volume)

        guard case .success(let changedVolume) = changedVolumeResult,
              (direction > 0 ? changedVolume.volume > volumeStatus.volume : changedVolume.volume < volumeStatus.volume) else {
            return XCTFail("TV did not apply diagnostic volume \(testVolume): \(changedVolumeResult)")
        }
        let restoreVolumeResult = await executeVolume(
            executor,
            target: volumeStatus.volume,
            current: changedVolume.volume
        )
        guard case .success(let restoredVolume) = restoreVolumeResult,
              restoredVolume.volume == volumeStatus.volume else {
            return XCTFail("Could not restore original volume \(volumeStatus.volume): \(restoreVolumeResult)")
        }

        let muteResult = await getMuted(client)
        if case .success(let originalMute) = muteResult {
            let changedMuteResult = await setMuted(client, muted: !originalMute)
            let observedMuteResult = await getMuted(client)
            let restoreMuteResult = await setMuted(client, muted: originalMute)
            guard case .success = changedMuteResult,
                  case .success(let observedMute) = observedMuteResult,
                  observedMute == !originalMute,
                  case .success = restoreMuteResult else {
                return XCTFail("Mute diagnostic failed or could not restore original state.")
            }
        }

        let volumeSubscription = expectation(description: "Initial volume subscription update")
        var subscribedVolume: LGResult<TVVolumeStatus>?
        client.subscribeVolume { result in
            guard subscribedVolume == nil else { return }
            subscribedVolume = result
            volumeSubscription.fulfill()
        }
        await fulfillment(of: [volumeSubscription], timeout: 8)
        guard let subscribedVolume, case .success = subscribedVolume else {
            return XCTFail("Volume subscription failed: \(String(describing: subscribedVolume))")
        }

        let muteSubscription = expectation(description: "Initial mute subscription update")
        var subscribedMute: LGResult<Bool>?
        client.subscribeMuted { result in
            guard subscribedMute == nil else { return }
            subscribedMute = result
            muteSubscription.fulfill()
        }
        await fulfillment(of: [muteSubscription], timeout: 12)
        guard let subscribedMute, case .success = subscribedMute else {
            return XCTFail("Mute subscription failed: \(String(describing: subscribedMute))")
        }

        let inputsResult = await getExternalInputs(client)
        guard case .success(let inputs) = inputsResult else {
            return XCTFail("Could not read external inputs: \(inputsResult)")
        }
        XCTAssertFalse(inputs.filter { $0.hdmiIndex != nil }.isEmpty)

        let inputSubscription = expectation(description: "Initial external input subscription update")
        var subscribedInputs: LGResult<[TVExternalInput]>?
        client.subscribeExternalInputs { result in
            guard subscribedInputs == nil else { return }
            subscribedInputs = result
            inputSubscription.fulfill()
        }
        await fulfillment(of: [inputSubscription], timeout: 8)
        guard let subscribedInputs, case .success = subscribedInputs else {
            return XCTFail("External input subscription failed: \(String(describing: subscribedInputs))")
        }

        let foregroundSubscription = expectation(description: "Initial foreground input subscription update")
        var foregroundResult: LGResult<String>?
        client.subscribeForegroundAppID { result in
            guard foregroundResult == nil else { return }
            foregroundResult = result
            foregroundSubscription.fulfill()
        }
        await fulfillment(of: [foregroundSubscription], timeout: 8)
        guard let foregroundResult, case .success(let foregroundAppID) = foregroundResult else {
            return XCTFail("Foreground input subscription failed: \(String(describing: foregroundResult))")
        }

        let currentHDMI = inputs.first {
            !$0.appID.isEmpty && $0.appID.caseInsensitiveCompare(foregroundAppID) == .orderedSame
        }?.hdmiIndex ?? WebOSClient.hdmiIndex(in: foregroundAppID)
        guard let currentHDMI else {
            throw XCTSkip("Current foreground input is not HDMI; skipping non-disruptive HDMI switch.")
        }
        let currentInputID = inputs.first(where: { $0.hdmiIndex == currentHDMI })?.id
        let switchResult = await switchHDMI(client, index: currentHDMI, inputID: currentInputID)
        guard case .success = switchResult else {
            return XCTFail("Could not switch back to current HDMI \(currentHDMI): \(switchResult)")
        }

        let soundOutputResult = await getSoundOutput(client)
        guard case .success(let soundOutput) = soundOutputResult else {
            return XCTFail("Could not read sound output: \(soundOutputResult)")
        }

        let soundOutputSubscription = expectation(description: "Initial sound output subscription update")
        var subscribedSoundOutput: LGResult<String>?
        client.subscribeSoundOutput { result in
            guard subscribedSoundOutput == nil else { return }
            subscribedSoundOutput = result
            soundOutputSubscription.fulfill()
        }
        await fulfillment(of: [soundOutputSubscription], timeout: 8)
        guard let subscribedSoundOutput, case .success = subscribedSoundOutput else {
            return XCTFail("Sound output subscription failed: \(String(describing: subscribedSoundOutput))")
        }

        let setSoundOutputResult = await changeSoundOutput(client, output: soundOutput)
        guard case .success = setSoundOutputResult else {
            return XCTFail("Could not keep current sound output \(soundOutput): \(setSoundOutputResult)")
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

    private func executeVolume(
        _ executor: VolumeCommandExecutor,
        target: Int,
        current: Int
    ) async -> LGResult<TVVolumeStatus> {
        await withCheckedContinuation { continuation in
            executor.execute(target: target, current: current) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func getMuted(_ client: WebOSClient) async -> LGResult<Bool> {
        await withCheckedContinuation { continuation in
            client.getMuted { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func setMuted(_ client: WebOSClient, muted: Bool) async -> LGResult<Void> {
        await withCheckedContinuation { continuation in
            client.setMuted(muted) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func getExternalInputs(_ client: WebOSClient) async -> LGResult<[TVExternalInput]> {
        await withCheckedContinuation { continuation in
            client.getExternalInputs { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func switchHDMI(_ client: WebOSClient, index: Int, inputID: String?) async -> LGResult<Void> {
        await withCheckedContinuation { continuation in
            client.switchHDMI(index, inputID: inputID) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func getSoundOutput(_ client: WebOSClient) async -> LGResult<String> {
        await withCheckedContinuation { continuation in
            client.getSoundOutput { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func changeSoundOutput(_ client: WebOSClient, output: String) async -> LGResult<Void> {
        await withCheckedContinuation { continuation in
            client.changeSoundOutput(output) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
