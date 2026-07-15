import XCTest
@testable import LGVolume

@MainActor
final class VolumeCommandExecutorTests: XCTestCase {
    func testVerifiesSuccessfulNativeStep() {
        let controller = FakeVolumeController(volumes: [51])
        let executor = makeExecutor(controller)
        var result: LGResult<TVVolumeStatus>?

        executor.execute(target: 51, current: 50) { result = $0 }

        XCTAssertEqual(controller.stepDeltas, [1])
        XCTAssertTrue(controller.absoluteTargets.isEmpty)
        XCTAssertEqual(result?.value?.volume, 51)
    }

    func testNativeStepAcceptsTVReportedJumpWithoutAbsoluteFallback() {
        let controller = FakeVolumeController(volumes: [53])
        let executor = makeExecutor(controller)
        var result: LGResult<TVVolumeStatus>?

        executor.execute(target: 51, current: 50) { result = $0 }

        XCTAssertEqual(controller.stepDeltas, [1])
        XCTAssertTrue(controller.absoluteTargets.isEmpty)
        XCTAssertEqual(result?.value?.volume, 53)
    }

    func testNativeStepDoesNotFallbackToAbsoluteVolumeWhenTVIsUnchanged() {
        let controller = FakeVolumeController(volumes: [50])
        let executor = makeExecutor(controller)
        var result: LGResult<TVVolumeStatus>?

        executor.execute(target: 51, current: 50) { result = $0 }

        XCTAssertEqual(controller.stepDeltas, [1])
        XCTAssertTrue(controller.absoluteTargets.isEmpty)
        guard case .failure(let message) = result else {
            return XCTFail("Expected verified failure")
        }
        XCTAssertEqual(message, "not applied")
    }

    func testRetriesWithSteppedVolumeWhenAbsoluteResponseDidNotChangeTV() {
        let controller = FakeVolumeController(volumes: [20, 20, 60])
        let executor = makeExecutor(controller)
        var result: LGResult<TVVolumeStatus>?

        executor.execute(target: 60, current: 20) { result = $0 }

        XCTAssertEqual(controller.absoluteTargets, [60])
        XCTAssertEqual(controller.stepDeltas, [40])
        XCTAssertEqual(result?.value?.volume, 60)
    }

    private func makeExecutor(_ controller: FakeVolumeController) -> VolumeCommandExecutor {
        VolumeCommandExecutor(
            controller: controller,
            logger: DiagnosticsLogger(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("LGVolumeVolumeTests-\(UUID().uuidString)")
            ),
            delay: { _, action in action() },
            verificationFailure: { "not applied" }
        )
    }
}

@MainActor
private final class FakeVolumeController: TVVolumeControlling {
    private var volumes: [Int]
    var absoluteTargets: [Int] = []
    var stepDeltas: [Int] = []

    init(volumes: [Int]) {
        self.volumes = volumes
    }

    func getVolume(completion: @escaping (LGResult<TVVolumeStatus>) -> Void) {
        let volume = volumes.isEmpty ? 50 : volumes.removeFirst()
        completion(.success(TVVolumeStatus(volume: volume, muted: false)))
    }

    func setVolume(_ volume: Int, completion: @escaping (LGResult<Void>) -> Void) {
        absoluteTargets.append(volume)
        completion(.success(()))
    }

    func changeVolume(delta: Int, completion: @escaping (LGResult<Void>) -> Void) {
        stepDeltas.append(delta)
        completion(.success(()))
    }
}

private extension LGResult {
    var value: Value? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}
