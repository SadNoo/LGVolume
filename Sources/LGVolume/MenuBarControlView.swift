import SwiftUI

struct MenuBarControlView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            volumeControls
            actionList
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(headerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(coordinator.isConnected ? .primary : .secondary)
                .lineLimit(1)

            Image(systemName: "circle.fill")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(statusColor)
                .accessibilityLabel(coordinator.isConnected ? coordinator.text(.connected) : coordinator.text(.currentDisconnected))

            Spacer(minLength: 8)
        }
    }

    private var volumeControls: some View {
        HStack(spacing: 7) {
            Button {
                coordinator.toggleMuteFromPanel()
            } label: {
                Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!coordinator.isConnected)
            .accessibilityLabel(coordinator.menuMuted ? coordinator.text(.turnMuteOff) : coordinator.text(.turnMuteOn))

            Text(coordinator.text(.volume))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text(displayVolumeText)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    private var actionList: some View {
        VStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { index in
                let selected = coordinator.selectedHDMIIndex == index + 1
                Button {
                    coordinator.switchHDMIFromPanel(index: index + 1)
                } label: {
                    Label(
                        coordinator.menuHDMINames[safe: index] ?? "HDMI\(index + 1)",
                        systemImage: selected ? "checkmark.circle.fill" : "circle"
                    )
                    .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(.bordered)
                .tint(selected ? .accentColor : nil)
                .disabled(!coordinator.isConnected)
            }

            if !coordinator.isConnected {
                Button {
                    coordinator.reconnect()
                } label: {
                    Label(
                        coordinator.isConnecting ? coordinator.text(.startPairing) : coordinator.text(.pairConnect),
                        systemImage: coordinator.isConnecting ? "arrow.triangle.2.circlepath" : "link"
                    )
                    .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.isConnecting)
            }

            Divider()

            Button {
                coordinator.showSettings()
            } label: {
                Label(coordinator.text(.settings), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(",", modifiers: .command)

            Button {
                coordinator.quit()
            } label: {
                Label(coordinator.text(.quit), systemImage: "power")
                    .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var headerTitle: String {
        if coordinator.isConnecting {
            return coordinator.text(.startPairing)
        }
        if coordinator.isConnected {
            return coordinator.menuTitle
        }
        return coordinator.text(.currentDisconnected)
    }

    private var statusColor: Color {
        if coordinator.isConnecting {
            return .orange
        }
        return coordinator.isConnected ? .green : .secondary.opacity(0.55)
    }

    private var displayVolumeText: String {
        if coordinator.menuMuted {
            return coordinator.text(.muted)
        }
        return "\(coordinator.menuVolume)%"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
