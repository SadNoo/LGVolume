import AppKit
import SwiftUI
import XCTest
@testable import LGVolume

@MainActor
final class VisualPreviewTests: XCTestCase {
    func testRenderSettingsAndMenuPreviews() throws {
        let coordinator = AppCoordinator()
        let settings = AppSettings()
        let settingsController = SettingsWindowController(settings: settings, coordinator: coordinator)
        settingsController.showWindow(nil)
        settingsController.refresh()

        let outputDirectory = previewDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let settingsWindow = try XCTUnwrap(settingsController.window)
        settingsWindow.layoutIfNeeded()
        let settingsView = try XCTUnwrap(settingsWindow.contentView)
        let settingsSize = NSSize(width: 720, height: 390)
        try render(settingsView, size: settingsSize, to: outputDirectory.appendingPathComponent("settings-general.png"))
        settingsWindow.appearance = NSAppearance(named: .darkAqua)
        settingsController.refresh()
        try render(settingsView, size: settingsSize, to: outputDirectory.appendingPathComponent("settings-general-dark.png"))
        settingsWindow.appearance = NSAppearance(named: .aqua)
        settingsController.refresh()
        let pageControl = try XCTUnwrap(findSegmentedControl(in: settingsView))
        for (segment, filename) in [
            (1, "settings-preferences.png"),
            (2, "settings-hdmi.png"),
            (3, "settings-shortcuts.png")
        ] {
            pageControl.selectedSegment = segment
            _ = pageControl.target?.perform(pageControl.action, with: pageControl)
            settingsWindow.layoutIfNeeded()
            try render(settingsView, size: settingsSize, to: outputDirectory.appendingPathComponent(filename))
        }
        settingsController.close()

        let menuView = NSHostingView(
            rootView: MenuBarControlView(coordinator: coordinator)
                .frame(width: 184)
                .padding(1)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        let menuSize = NSSize(width: 186, height: max(menuView.fittingSize.height, 360))
        try render(menuView, size: menuSize, to: outputDirectory.appendingPathComponent("menu-panel.png"))
    }

    private func previewDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["LGVOLUME_PREVIEW_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("LGVolumePreviews", isDirectory: true)
    }

    private func render(_ view: NSView, size: NSSize, to url: URL) throws {
        view.frame = NSRect(origin: .zero, size: size)
        view.wantsLayer = true
        var backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        view.layer?.backgroundColor = backgroundColor
        view.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
        XCTAssertGreaterThan(png.count, 1_000)
    }

    private func findSegmentedControl(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl, control.segmentCount == 4 {
            return control
        }
        for subview in view.subviews {
            if let control = findSegmentedControl(in: subview) {
                return control
            }
        }
        return nil
    }
}
