import AppKit
import SwiftUI
import XCTest
@testable import LGVolume

@MainActor
final class VisualPreviewTests: XCTestCase {
    func testRenderSettingsAndMenuPreviews() throws {
        let suiteName = "local.codex.lgvolume.visual-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, tokenStore: MemoryPairingTokenStore())
        settings.tvIP = "192.168.1.20"
        settings.tvName = "LG TV"
        settings.setHDMIName("Living Room Apple TV", index: 2)
        settings.languageMode = "zh-Hans"
        let coordinator = AppCoordinator(settings: settings)
        let settingsController = SettingsWindowController(settings: settings, coordinator: coordinator)
        settingsController.showWindow(nil)
        settingsController.refresh()

        let outputDirectory = previewDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let settingsWindow = try XCTUnwrap(settingsController.window)
        let settingsView = try XCTUnwrap(settingsWindow.contentView)
        let settingsSize = NSSize(width: 720, height: 390)
        settingsView.frame.size = settingsSize
        settingsWindow.layoutIfNeeded()
        assertVisibleControl("settings.ip", in: settingsView)
        assertVisibleControl("settings.name", in: settingsView)
        assertVisibleControl("settings.save", in: settingsView)
        assertFormGrid(in: settingsView)
        assertLeadingEdges([
            "settings.ip",
            "settings.name",
            "settings.ipFeedback",
            "settings.generalActions"
        ], in: settingsView)
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
            assertFormGrid(in: settingsView)
            if segment == 1 {
                assertLeadingEdges([
                    "settings.appearance",
                    "settings.language",
                    "settings.launchAtLogin",
                    "settings.secureConnection",
                    "settings.diagnostics"
                ], in: settingsView)
            } else if segment == 2 {
                assertVisibleControl("settings.useTVInputNames", in: settingsView)
                assertVisibleControl("settings.detectedInputNames", in: settingsView)
                for index in 1...4 {
                    assertVisibleControl("settings.hdmiName\(index)", in: settingsView)
                }
                assertLeadingEdges([
                    "settings.useTVInputNames",
                    "settings.detectedInputNames",
                    "settings.hdmiName1",
                    "settings.hdmiName2",
                    "settings.hdmiName3",
                    "settings.hdmiName4"
                ], in: settingsView)
            } else if segment == 3 {
                assertLeadingEdges((1...4).map { "settings.hdmiShortcut\($0)" } + [
                    "settings.restoreHDMIShortcuts"
                ], in: settingsView)
            }
            try render(settingsView, size: settingsSize, to: outputDirectory.appendingPathComponent(filename))
            settingsWindow.appearance = NSAppearance(named: .darkAqua)
            settingsWindow.layoutIfNeeded()
            let darkFilename = filename.replacingOccurrences(of: ".png", with: "-dark.png")
            try render(settingsView, size: settingsSize, to: outputDirectory.appendingPathComponent(darkFilename))
            settingsWindow.appearance = NSAppearance(named: .aqua)
            settingsWindow.layoutIfNeeded()
        }
        settingsController.close()

        let menuView = NSHostingView(
            rootView: MenuBarControlView(coordinator: coordinator)
                .frame(width: coordinator.menuPreferredWidth)
                .padding(1)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        XCTAssertGreaterThan(coordinator.menuPreferredWidth, 184)
        XCTAssertLessThanOrEqual(coordinator.menuPreferredWidth, 240)
        menuView.wantsLayer = true
        let menuSize = NSSize(width: 186, height: max(menuView.fittingSize.height, 360))
        let menuWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: menuSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        menuWindow.contentView = menuView
        menuWindow.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        menuWindow.layoutIfNeeded()
        menuView.layoutSubtreeIfNeeded()
        menuView.displayIfNeeded()
        try render(menuView, size: menuSize, to: outputDirectory.appendingPathComponent("menu-panel.png"))
        menuWindow.orderOut(nil)
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
        XCTAssertEqual(representation.size.width, size.width, accuracy: 0.5)
        XCTAssertEqual(representation.size.height, size.height, accuracy: 0.5)
        XCTAssertGreaterThan(sampledColorCount(in: representation), 2)
        XCTAssertGreaterThan(sampledLuminanceRange(in: representation), 0.35)
    }

    private func sampledColorCount(in image: NSBitmapImageRep) -> Int {
        var colors = Set<String>()
        let xStep = max(image.pixelsWide / 24, 1)
        let yStep = max(image.pixelsHigh / 16, 1)
        for y in stride(from: 0, to: image.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: image.pixelsWide, by: xStep) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                colors.insert(String(format: "%.3f,%.3f,%.3f,%.3f", color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent))
            }
        }
        return colors.count
    }

    private func sampledLuminanceRange(in image: NSBitmapImageRep) -> CGFloat {
        var minimum: CGFloat = 1
        var maximum: CGFloat = 0
        let xStep = max(image.pixelsWide / 120, 1)
        let yStep = max(image.pixelsHigh / 80, 1)
        for y in stride(from: 0, to: image.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: image.pixelsWide, by: xStep) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = (
                    0.2126 * color.redComponent
                        + 0.7152 * color.greenComponent
                        + 0.0722 * color.blueComponent
                ) * color.alphaComponent
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
            }
        }
        return maximum - minimum
    }

    private func assertVisibleControl(_ identifier: String, in root: NSView, file: StaticString = #filePath, line: UInt = #line) {
        guard let view = findView(identifier: identifier, in: root) else {
            return XCTFail("Missing view \(identifier)", file: file, line: line)
        }
        let frame = view.convert(view.bounds, to: root)
        XCTAssertGreaterThan(frame.width, 1, file: file, line: line)
        XCTAssertGreaterThan(frame.height, 1, file: file, line: line)
        XCTAssertFalse(view.isHidden, file: file, line: line)
        XCTAssertGreaterThan(view.alphaValue, 0, file: file, line: line)
        XCTAssertTrue(root.bounds.contains(frame), "Clipped view \(identifier): \(frame)", file: file, line: line)
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        return root.subviews.lazy.compactMap { self.findView(identifier: identifier, in: $0) }.first
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

    private func assertFormGrid(
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let grid = findGridView(in: root) else {
            return XCTFail("Missing settings form grid", file: file, line: line)
        }
        XCTAssertEqual(grid.columnSpacing, 10, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(grid.rowAlignment, .none, file: file, line: line)
        XCTAssertEqual(grid.yPlacement, .center, file: file, line: line)
        XCTAssertEqual(grid.column(at: 0).width, 120, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(grid.column(at: 0).xPlacement, .leading, file: file, line: line)
        var labelLeadingEdges: [CGFloat] = []
        for rowIndex in 0..<grid.numberOfRows {
            let row = grid.row(at: rowIndex)
            XCTAssertEqual(row.yPlacement, .center, file: file, line: line)
            guard let label = row.cell(at: 0).contentView,
                  let control = row.cell(at: 1).contentView else { continue }
            let labelFrame = visibleAlignmentFrame(of: label, in: root)
            let controlFrame = visibleAlignmentFrame(of: control, in: root)
            labelLeadingEdges.append(labelFrame.minX)
            XCTAssertEqual(labelFrame.midY, controlFrame.midY, accuracy: 0.5, file: file, line: line)
            if let textField = label as? NSTextField {
                XCTAssertTrue(
                    textField.stringValue.hasSuffix(":") || textField.stringValue.hasSuffix("："),
                    "Missing form-label separator: \(textField.stringValue)",
                    file: file,
                    line: line
                )
            }
        }
        if let reference = labelLeadingEdges.first {
            for position in labelLeadingEdges.dropFirst() {
                XCTAssertEqual(position, reference, accuracy: 0.5, file: file, line: line)
            }
        }
    }

    private func assertLeadingEdges(
        _ identifiers: [String],
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let positions = identifiers.compactMap { identifier -> CGFloat? in
            guard let view = findView(identifier: identifier, in: root) else {
                XCTFail("Missing view \(identifier)", file: file, line: line)
                return nil
            }
            return visibleAlignmentFrame(of: view, in: root).minX
        }
        guard let reference = positions.first else { return }
        for position in positions.dropFirst() {
            XCTAssertEqual(position, reference, accuracy: 0.5, file: file, line: line)
        }
    }

    private func findGridView(in view: NSView) -> NSGridView? {
        if let grid = view as? NSGridView { return grid }
        return view.subviews.lazy.compactMap { self.findGridView(in: $0) }.first
    }

    private func visibleAlignmentFrame(of view: NSView, in root: NSView) -> NSRect {
        let frame = view.convert(view.bounds, to: root)
        let insets = view.alignmentRectInsets
        return NSRect(
            x: frame.minX + insets.left,
            y: frame.minY + insets.bottom,
            width: frame.width - insets.left - insets.right,
            height: frame.height - insets.top - insets.bottom
        )
    }
}
