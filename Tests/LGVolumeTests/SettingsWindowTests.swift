import AppKit
import XCTest
@testable import LGVolume

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testChangingLanguageKeepsTheCurrentPage() throws {
        let suiteName = "local.codex.lgvolume.settings-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())
        settings.languageMode = "zh-Hans"
        let coordinator = AppCoordinator(settings: settings)
        let controller = SettingsWindowController(settings: settings, coordinator: coordinator)
        controller.showWindow(nil)
        defer { controller.close() }

        let sidebar = try XCTUnwrap(findTable(in: try XCTUnwrap(controller.window?.contentView)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        controller.selectPage(1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(sidebar.selectedRow, 1)

        // Clicking a sidebar row leaves the table as first responder.
        controller.window?.makeFirstResponder(sidebar)
        coordinator.setLanguageMode("en")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(sidebar.selectedRow, 1, "Changing the language must stay on Preferences")
        let content = try XCTUnwrap(controller.window?.contentView)
        XCTAssertNotNil(find("settings.language", in: content), "Preferences content must still be shown")
        XCTAssertNil(find("settings.ip", in: content), "General content must not be shown")
        coordinator.setLanguageMode("ja")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(sidebar.selectedRow, 1)
    }

    private func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier, view.window != nil { return view }
        for subview in view.subviews {
            if let match = find(identifier, in: subview) { return match }
        }
        return nil
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.identifier?.rawValue == "settings.sidebar" {
            return table
        }
        for subview in view.subviews {
            if let table = findTable(in: subview) { return table }
        }
        return nil
    }
}
