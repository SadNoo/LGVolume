import Foundation
import XCTest
@testable import LGVolume

final class AppSettingsTests: XCTestCase {
    func testDisabledShortcutDoesNotRestoreDefault() {
        let suiteName = "local.codex.lgvolume.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertNotNil(settings.hdmiShortcut(1))
        settings.setHDMIShortcut(nil, index: 1)
        XCTAssertNil(settings.hdmiShortcut(1))

        settings.resetHDMIShortcuts()
        XCTAssertNotNil(settings.hdmiShortcut(1))
    }
}
