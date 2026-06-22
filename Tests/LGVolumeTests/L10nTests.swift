import XCTest
@testable import LGVolume

final class L10nTests: XCTestCase {
    func testEveryLanguageHasTextForEveryKey() {
        for language in ["zh-Hans", "en", "ja"] {
            for key in L10n.Key.allCases {
                XCTAssertFalse(
                    L10n.text(key, languageMode: language).isEmpty,
                    "Missing \(key) in \(language)"
                )
            }
        }
    }
}
