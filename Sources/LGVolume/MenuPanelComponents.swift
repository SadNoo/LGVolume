import AppKit
import SwiftUI

/// Volume bar shared by the panel styles. Dragging sends targets as the value changes; the bar
/// follows the pointer while dragging and the TV's read-back afterwards.
struct PanelVolumeBar: View {
    @ObservedObject var coordinator: AppCoordinator
    var thickness: CGFloat
    var vertical = false
    /// Thick Control Center bars use a white fill with the speaker glyph inside (tap to mute);
    /// thin bars use the accent colour like a native slider.
    var prominent = false
    @State private var dragging: Double?
    @Environment(\.colorScheme) private var scheme

    private var value: Double {
        dragging ?? Double(coordinator.menuVolume)
    }

    var body: some View {
        GeometryReader { geometry in
            let length = vertical ? geometry.size.height : geometry.size.width
            ZStack(alignment: vertical ? .bottom : .leading) {
                track
                fill
                    .frame(
                        width: vertical ? nil : max(prominent ? thickness : 0, length * value / 100),
                        height: vertical ? max(prominent ? 44 : 0, length * value / 100) : nil
                    )
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.primary.opacity(prominent ? 0.08 : 0), lineWidth: 1))
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let position = vertical ? length - gesture.location.y : gesture.location.x
                        let newValue = min(max(position / max(length, 1) * 100, 0), 100)
                        let previous = dragging?.rounded()
                        dragging = newValue
                        if newValue.rounded() != previous {
                            coordinator.setVolumeFromPanel(Int(newValue.rounded()))
                        }
                    }
                    .onEnded { _ in dragging = nil }
            )
            .overlay(alignment: vertical ? .bottom : .leading) {
                if prominent {
                    muteGlyphButton
                        .frame(width: thickness, height: vertical ? 44 : thickness)
                }
            }
        }
        .frame(width: vertical ? thickness : nil, height: vertical ? nil : thickness)
        .disabled(!coordinator.isConnected)
        .opacity(coordinator.isConnected ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel(coordinator.text(.volume))
        .accessibilityValue(coordinator.isConnected ? "\(coordinator.menuVolume)%" : "—")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: coordinator.adjustVolumeFromPanel(delta: 1)
            case .decrement: coordinator.adjustVolumeFromPanel(delta: -1)
            @unknown default: break
            }
        }
    }

    private var shape: AnyShape {
        vertical ? AnyShape(RoundedRectangle(cornerRadius: 16)) : AnyShape(Capsule())
    }

    private var track: some View {
        shape.fill(Color.primary.opacity(scheme == .dark ? 0.14 : 0.16))
    }

    @ViewBuilder
    private var fill: some View {
        if prominent {
            Rectangle().fill(Color.white)
        } else {
            Rectangle().fill(Color.accentColor)
        }
    }

    private var muteGlyphButton: some View {
        Button {
            coordinator.toggleMuteFromPanel()
        } label: {
            Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: vertical ? 17 : thickness * 0.46, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(coordinator.menuMuted ? coordinator.text(.turnMuteOff) : coordinator.text(.turnMuteOn))
    }
}

/// Plain mute button with the speaker glyph reflecting the TV's mute state.
struct PanelMuteButton: View {
    @ObservedObject var coordinator: AppCoordinator
    var size: CGFloat = 26
    var filled = true

    var body: some View {
        Button {
            coordinator.toggleMuteFromPanel()
        } label: {
            Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? Color.primary.opacity(0.09) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.isConnected)
        .help(coordinator.menuMuted ? coordinator.text(.turnMuteOff) : coordinator.text(.turnMuteOn))
        .accessibilityLabel(coordinator.menuMuted ? coordinator.text(.turnMuteOff) : coordinator.text(.turnMuteOn))
    }
}

/// Volume read-out: "—" while disconnected so a stale value never looks live.
struct PanelVolumeText: View {
    @ObservedObject var coordinator: AppCoordinator
    var font: Font

    var body: some View {
        Text(text)
            .font(font.monospacedDigit())
            .contentTransition(.numericText())
    }

    private var text: String {
        guard coordinator.isConnected else { return "—" }
        return coordinator.menuMuted ? coordinator.text(.muted) : "\(coordinator.menuVolume)%"
    }
}

/// Shows the TV's sound outputs in a native pop-up menu at the pointer.
enum SoundOutputMenu {
    @MainActor
    static func show(for coordinator: AppCoordinator) {
        let menu = NSMenu()
        for option in coordinator.soundOutputOptions {
            menu.addItem(ClosureMenuItem(
                title: coordinator.soundOutputTitle(option),
                checked: option.id == coordinator.currentSoundOutputID
            ) {
                coordinator.changeSoundOutput(option.id)
            })
        }
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let location = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: location, in: view)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, checked: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}

/// A row-shaped button that opens the sound output menu.
struct SoundOutputButton<Label: View>: View {
    @ObservedObject var coordinator: AppCoordinator
    @ViewBuilder var label: Label

    var body: some View {
        Button {
            SoundOutputMenu.show(for: coordinator)
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.soundOutputAvailable)
        .opacity(coordinator.soundOutputAvailable ? 1 : 0.45)
        .accessibilityLabel("\(coordinator.text(.soundOutput)) \(coordinator.currentSoundOutputTitle)")
    }
}

/// Disconnected / error notice with the actions that resolve it.
struct ConnectionBanner: View {
    @ObservedObject var coordinator: AppCoordinator
    var showsActions = true

    var body: some View {
        if !coordinator.isConnected || coordinator.statusIsError {
            HStack(alignment: .top, spacing: 7) {
                if coordinator.isConnecting {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                } else {
                    Image(systemName: coordinator.statusIsError ? "exclamationmark.triangle.fill" : "wifi.exclamationmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(coordinator.statusIsError ? Color.orange : Color.secondary)
                        .padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    if showsActions && !coordinator.isConnected && !coordinator.isConnecting {
                        HStack(spacing: 6) {
                            CapsuleButton(title: coordinator.text(.reconnect), prominent: true) {
                                coordinator.reconnect()
                            }
                            CapsuleButton(title: coordinator.text(.settingsEllipsis)) {
                                coordinator.showSettings()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(coordinator.statusIsError ? Color.orange.opacity(0.13) : Color.primary.opacity(0.06))
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var message: String {
        if coordinator.isConnecting {
            return coordinator.text(.connecting)
        }
        if coordinator.statusIsError {
            return coordinator.status
        }
        return coordinator.text(.notConnectedTV)
    }
}

struct CapsuleButton: View {
    var title: String
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Small switch drawn in SwiftUI so it looks the same in the non-key menu bar panel.
struct MiniSwitch: View {
    var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.18))
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(Color.white).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5).padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// "Standby with Mac" switch row, with a hint when the pairing lacks the power permission.
struct SleepSyncRow: View {
    @ObservedObject var coordinator: AppCoordinator
    var showsIcon = true
    var fontSize: CGFloat = 12

    var body: some View {
        Button {
            coordinator.setSleepTVWithMac(!coordinator.sleepTVWithMac)
        } label: {
            HStack(spacing: 6) {
                if showsIcon {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(coordinator.text(.sleepTVShort)).font(.system(size: fontSize))
                    if coordinator.sleepTVNeedsRepair {
                        Text(coordinator.text(.needsRepairShort))
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                MiniSwitch(isOn: coordinator.sleepTVWithMac)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(coordinator.text(.sleepTVWithMacHelp))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coordinator.text(.sleepTVShort))
        .accessibilityValue(coordinator.sleepTVWithMac ? "1" : "0")
        .accessibilityAddTraits(.isButton)
    }
}

/// Settings and Quit, with the usual ⌘, and ⌘Q.
struct PanelFooter: View {
    @ObservedObject var coordinator: AppCoordinator
    var iconsOnly = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.showSettings()
            } label: {
                if iconsOnly {
                    Image(systemName: "gearshape")
                } else {
                    Label(coordinator.text(.settingsEllipsis), systemImage: "gearshape")
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            .help(coordinator.text(.settings))

            if !iconsOnly { Spacer() }

            Button {
                coordinator.quit()
            } label: {
                if iconsOnly {
                    Image(systemName: "power")
                } else {
                    Label(coordinator.text(.quit), systemImage: "power")
                }
            }
            .keyboardShortcut("q", modifiers: .command)
            .help(coordinator.text(.quitApp))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

struct IconCircle: View {
    var symbol: String
    var active: Bool
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.75))
            .frame(width: size, height: size)
            .background(Circle().fill(active ? Color.accentColor : Color.primary.opacity(0.1)))
    }
}

struct MacBadge: View {
    var body: some View {
        Text("Mac")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .foregroundStyle(.secondary)
            .background(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 0.8))
            .accessibilityLabel("Mac")
    }
}

struct PanelModule<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.75))
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 2, y: 1)
            )
    }
}

/// Highlights a row while the pointer is over it, like a menu item.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    var enabled = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(hovering && enabled ? Color.primary.opacity(0.08) : .clear)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 6, enabled: Bool = true) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, enabled: enabled))
    }
}

/// One HDMI input's data, gathered from the coordinator for the panel styles.
struct PanelInput: Identifiable {
    let index: Int
    let name: String
    let symbol: String
    let isSelected: Bool
    let isMac: Bool
    let isPresent: Bool
    let shortcut: String?
    var id: Int { index }

    @MainActor
    static func all(from coordinator: AppCoordinator) -> [PanelInput] {
        (1...4).map { index in
            PanelInput(
                index: index,
                name: coordinator.menuHDMINames.indices.contains(index - 1)
                    ? coordinator.menuHDMINames[index - 1]
                    : "HDMI\(index)",
                symbol: coordinator.inputSymbol(index),
                isSelected: coordinator.isConnected && coordinator.selectedHDMIIndex == index,
                isMac: coordinator.effectiveMacHDMIPort == index,
                isPresent: coordinator.isInputConnected(index),
                shortcut: coordinator.shortcutDisplay(index)
            )
        }
    }
}
