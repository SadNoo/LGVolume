import AppKit

final class VolumePanelController: NSWindowController {
    private static let panelSize = NSSize(width: 360, height: 158)

    private let volumeView = VolumePanelView(frame: NSRect(origin: .zero, size: panelSize))
    private weak var coordinator: AppCoordinator?
    private var autoCloseTimer: Timer?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        super.init(window: panel)
        panel.contentView = volumeView

        volumeView.onMute = { [weak self] in
            self?.scheduleAutoClose()
            self?.coordinator?.toggleMuteFromPanel()
        }
        volumeView.onVolumeCommit = { [weak self] volume in
            self?.scheduleAutoClose()
            self?.coordinator?.setVolumeFromPanel(volume)
        }
        volumeView.onHDMI = { [weak self] index in
            self?.scheduleAutoClose()
            self?.coordinator?.switchHDMIFromPanel(index: index)
        }
        volumeView.onInteraction = { [weak self] in
            self?.scheduleAutoClose()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle(anchor: NSStatusBarButton, title: String, volume: Int, muted: Bool, hdmiNames: [String]) {
        if window?.isVisible == true {
            window?.orderOut(nil)
            return
        }
        update(title: title, volume: volume, muted: muted, hdmiNames: hdmiNames)
        position(anchor: anchor)
        window?.orderFrontRegardless()
        scheduleAutoClose()
    }

    func update(title: String, volume: Int, muted: Bool, hdmiNames: [String]) {
        volumeView.title = "LG TV"
        volumeView.volume = volume
        volumeView.muted = muted
        volumeView.hdmiNames = hdmiNames
        if window?.isVisible == true {
            scheduleAutoClose()
        }
    }

    func showFeedback(delta: Int) {
        volumeView.showFeedback(delta: delta)
    }

    func refreshAppearance() {
        volumeView.needsDisplay = true
    }

    private func position(anchor: NSStatusBarButton) {
        guard let window, let anchorWindow = anchor.window else { return }
        let anchorRect = anchor.convert(anchor.bounds, to: nil)
        let screenRect = anchorWindow.convertToScreen(anchorRect)
        let visible = (anchorWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = screenRect.midX - window.frame.width / 2
        x = min(max(x, visible.minX + 12), visible.maxX - window.frame.width - 12)
        let y = visible.maxY - window.frame.height - 18
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleAutoClose() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            guard let self, !self.volumeView.isDragging else { return }
            self.window?.orderOut(nil)
        }
    }
}

private final class VolumePanelView: NSView {
    var onMute: (() -> Void)?
    var onVolumeCommit: ((Int) -> Void)?
    var onHDMI: ((Int) -> Void)?
    var onInteraction: (() -> Void)?

    var title = "LG TV" { didSet { needsDisplay = true } }
    var volume = 50 {
        didSet {
            volume = min(max(volume, 0), 100)
            needsDisplay = true
        }
    }
    var muted = false { didSet { needsDisplay = true } }
    var hdmiNames = ["HDMI1", "HDMI2", "HDMI3", "HDMI4"] { didSet { needsDisplay = true } }

    private(set) var isDragging = false
    private var feedbackDirection = 0
    private var feedbackTimer: Timer?

    private var speakerRect: NSRect { NSRect(x: 26, y: 56, width: 26, height: 26) }
    private var rightSpeakerRect: NSRect { NSRect(x: 306, y: 56, width: 28, height: 26) }
    private var trackRect: NSRect { NSRect(x: 62, y: 66, width: 232, height: 5) }

    private var buttonRects: [NSRect] {
        [
            NSRect(x: 64, y: 94, width: 106, height: 24),
            NSRect(x: 190, y: 94, width: 106, height: 24),
            NSRect(x: 64, y: 124, width: 106, height: 24),
            NSRect(x: 190, y: 124, width: 106, height: 24)
        ]
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bodyRect = bounds.insetBy(dx: 2, dy: 2)
        let background = NSBezierPath(roundedRect: bodyRect, xRadius: 31, yRadius: 31)
        if !isDarkAppearance {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor(calibratedWhite: 1, alpha: 0.75)
            glow.shadowBlurRadius = 10
            glow.shadowOffset = .zero
            glow.set()
            NSColor(calibratedWhite: 1, alpha: 0.35).setFill()
            background.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        palette.background.setFill()
        background.fill()
        palette.border.setStroke()
        background.lineWidth = 0.9
        background.stroke()

        drawSoftTopHighlight(in: bodyRect)
        drawTitle()
        drawSpeaker(name: muted ? "speaker.slash.fill" : "speaker.fill", rect: speakerRect)
        drawSpeaker(name: muted ? "speaker.slash.fill" : "speaker.wave.3.fill", rect: rightSpeakerRect)
        drawTrack()
        drawHDMIButtons()
    }

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        let point = convert(event.locationInWindow, from: nil)
        if speakerRect.contains(point) {
            onMute?()
            return
        }
        if let hdmiIndex = hdmiIndex(at: point) {
            onHDMI?(hdmiIndex)
            return
        }
        guard hitTrack(point) else { return }
        isDragging = true
        updateVolume(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        onInteraction?()
        updateVolume(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        onInteraction?()
        isDragging = false
        updateVolume(convert(event.locationInWindow, from: nil))
        onVolumeCommit?(volume)
    }

    func showFeedback(delta: Int) {
        guard delta != 0 else { return }
        feedbackDirection = delta > 0 ? 1 : -1
        needsDisplay = true

        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            self?.feedbackDirection = 0
            self?.needsDisplay = true
        }
    }

    private func drawSoftTopHighlight(in rect: NSRect) {
        let topRect = NSRect(x: rect.minX + 14, y: rect.minY + 6, width: rect.width - 28, height: 18)
        let top = NSBezierPath(roundedRect: topRect, xRadius: 9, yRadius: 9)
        palette.highlight.setFill()
        top.fill()
    }

    private func drawTitle() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: palette.text
        ]
        (title as NSString).draw(at: NSPoint(x: 32, y: 22), withAttributes: attrs)
    }

    private func drawSpeaker(name: String, rect: NSRect) {
        let isLeft = rect.midX < bounds.midX
        let shouldFlash = (isLeft && feedbackDirection < 0) || (!isLeft && feedbackDirection > 0)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)) else {
            return
        }
        image.isTemplate = true
        (shouldFlash ? palette.flash : palette.icon).set()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawTrack() {
        let base = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)
        palette.track.setFill()
        base.fill()

        if !muted && volume > 0 {
            let fill = NSRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: max(5, trackRect.width * CGFloat(volume) / 100),
                height: trackRect.height
            )
            palette.trackFill.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
        }

        for index in 0..<17 {
            let progress = CGFloat(index) / 16
            let dotRect = NSRect(x: trackRect.minX + progress * trackRect.width - 1.1, y: 78, width: 2.2, height: 2.2)
            let active = !muted && progress <= CGFloat(volume) / 100
            (active ? palette.dotActive : palette.dot).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    private func drawHDMIButtons() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: palette.text
        ]

        for (offset, rect) in buttonRects.enumerated() {
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            palette.button.setFill()
            path.fill()
            palette.buttonBorder.setStroke()
            path.lineWidth = 0.7
            path.stroke()

            let name = offset < hdmiNames.count ? hdmiNames[offset] : "HDMI\(offset + 1)"
            let textSize = (name as NSString).size(withAttributes: attrs)
            let textPoint = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2)
            (name as NSString).draw(at: textPoint, withAttributes: attrs)
        }
    }

    private func hdmiIndex(at point: NSPoint) -> Int? {
        for (offset, rect) in buttonRects.enumerated() where rect.contains(point) {
            return offset + 1
        }
        return nil
    }

    private func hitTrack(_ point: NSPoint) -> Bool {
        trackRect.insetBy(dx: -10, dy: -14).contains(point)
    }

    private func updateVolume(_ point: NSPoint) {
        let previousVolume = volume
        let raw = (point.x - trackRect.minX) / trackRect.width
        volume = Int((min(max(raw, 0), 1) * 100).rounded())
        muted = false
        showFeedback(delta: volume - previousVolume)
    }

    private var isDarkAppearance: Bool {
        let appearance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return appearance == .darkAqua
    }

    private var palette: Palette {
        if isDarkAppearance {
            return Palette(
                background: NSColor(calibratedWhite: 0.12, alpha: 0.97),
                border: NSColor(calibratedWhite: 0.55, alpha: 0.88),
                highlight: NSColor(calibratedWhite: 1, alpha: 0.04),
                text: NSColor(calibratedWhite: 0.98, alpha: 1),
                icon: NSColor(calibratedWhite: 1, alpha: 0.96),
                flash: .white,
                track: NSColor(calibratedWhite: 0.31, alpha: 0.95),
                trackFill: NSColor(calibratedWhite: 0.98, alpha: 1),
                dot: NSColor(calibratedWhite: 0.25, alpha: 1),
                dotActive: NSColor(calibratedWhite: 0.55, alpha: 0.85),
                button: NSColor(calibratedWhite: 0.20, alpha: 0.96),
                buttonBorder: NSColor(calibratedWhite: 0.44, alpha: 0.65)
            )
        }
        return Palette(
            background: NSColor(calibratedWhite: 1.0, alpha: 0.72),
            border: NSColor(calibratedWhite: 0.70, alpha: 0.70),
            highlight: NSColor(calibratedWhite: 1, alpha: 0.42),
            text: NSColor(calibratedWhite: 0.08, alpha: 1),
            icon: NSColor(calibratedWhite: 0.05, alpha: 0.96),
            flash: NSColor(calibratedWhite: 0, alpha: 1),
            track: NSColor(calibratedWhite: 0.76, alpha: 0.68),
            trackFill: NSColor(calibratedWhite: 0.12, alpha: 1),
            dot: NSColor(calibratedWhite: 0.68, alpha: 0.75),
            dotActive: NSColor(calibratedWhite: 0.35, alpha: 0.85),
            button: NSColor(calibratedWhite: 0.96, alpha: 0.58),
            buttonBorder: NSColor(calibratedWhite: 0.58, alpha: 0.45)
        )
    }
}

private struct Palette {
    let background: NSColor
    let border: NSColor
    let highlight: NSColor
    let text: NSColor
    let icon: NSColor
    let flash: NSColor
    let track: NSColor
    let trackFill: NSColor
    let dot: NSColor
    let dotActive: NSColor
    let button: NSColor
    let buttonBorder: NSColor
}
