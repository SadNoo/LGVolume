import XCTest
@testable import LGVolume

final class VolumeWorkTests: XCTestCase {
    func testRapidKeyPressesAccumulateAsNativeSteps() {
        var work: VolumeWork?
        for _ in 0..<4 {
            work = VolumeWork.adding(steps: 1, to: work)
        }
        XCTAssertEqual(work, .steps(4))
    }

    func testAlternatingKeyPressesCancelOut() {
        var work = VolumeWork.adding(steps: 1, to: nil)
        work = VolumeWork.adding(steps: -1, to: work)
        XCTAssertNil(work)
    }

    func testKeyPressAdjustsQueuedSliderTargetAndStaysAbsolute() {
        XCTAssertEqual(VolumeWork.adding(steps: 1, to: .absolute(40)), .absolute(41))
        XCTAssertEqual(VolumeWork.adding(steps: 1, to: .absolute(100)), .absolute(100))
    }

    func testStepsAreSentInBoundedBatches() {
        let first = VolumeWork.takeBatch(from: .steps(-12))
        XCTAssertEqual(first.batch, .steps(-VolumeWork.maximumStepBatch))
        XCTAssertEqual(first.remainder, .steps(-12 + VolumeWork.maximumStepBatch))

        let last = VolumeWork.takeBatch(from: .steps(2))
        XCTAssertEqual(last.batch, .steps(2))
        XCTAssertNil(last.remainder)
    }

    func testAbsoluteTargetIsSentWhole() {
        let split = VolumeWork.takeBatch(from: .absolute(70))
        XCTAssertEqual(split.batch, .absolute(70))
        XCTAssertNil(split.remainder)
    }
}
