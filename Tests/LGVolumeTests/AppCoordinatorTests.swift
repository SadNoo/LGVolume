import XCTest
@testable import LGVolume

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testSoundOutputSubscriptionRejectsStaleValueWhileCommandIsPending() {
        XCTAssertFalse(
            AppCoordinator.shouldAcceptSoundOutputSubscription(
                reported: "tv_speaker",
                pending: "external_arc"
            )
        )
        XCTAssertTrue(
            AppCoordinator.shouldAcceptSoundOutputSubscription(
                reported: "external_arc",
                pending: "external_arc"
            )
        )
        XCTAssertTrue(
            AppCoordinator.shouldAcceptSoundOutputSubscription(
                reported: "tv_speaker",
                pending: nil
            )
        )
    }
}
