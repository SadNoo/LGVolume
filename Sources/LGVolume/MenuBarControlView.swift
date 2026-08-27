import SwiftUI

struct MenuBarControlView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            volumeControls
                .padding(.bottom, 10)

            Divider()
            soundOutputControl
                .padding(.vertical, 5)
            Divider()

            inputList

            if !coordinator.isConnected {
                Divider()
                reconnectButton
                    .padding(.vertical, 5)
            }

            Divider()
                .padding(.top, 5)
            footer
                .padding(.top, 8)
        }
        .padding(.horizontal, 13)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(headerTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(coordinator.isConnected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .accessibilityLabel(
                    coordinator.isConnected
                        ? coordinator.text(.connected)
                        : coordinator.text(.currentDisconnected)
                )

            Spacer(minLength: 8)

            Text(displayVolumeText)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    private var volumeControls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    coordinator.toggleMuteFromPanel()
                } label: {
                    Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!coordinator.isConnected)
                .accessibilityLabel(
                    coordinator.menuMuted
                        ? coordinator.text(.turnMuteOff)
                        : coordinator.text(.turnMuteOn)
                )

                Text(coordinator.text(.volume))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 7) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Slider(value: volumeBinding, in: 0...100, step: 1)
                    .disabled(!coordinator.isConnected)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var soundOutputControl: some View {
        Menu {
            ForEach(coordinator.soundOutputOptions) { output in
                Button {
                    coordinator.changeSoundOutput(output.id)
                } label: {
                    if coordinator.currentSoundOutputID == output.id {
                        Label(coordinator.soundOutputTitle(output), systemImage: "checkmark")
                    } else {
                        Text(coordinator.soundOutputTitle(output))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.2")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(coordinator.currentSoundOutputTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 27)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!coordinator.soundOutputAvailable)
        .accessibilityLabel(coordinator.text(.soundOutput))
    }

    private var inputList: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                inputButton(index)
            }
        }
    }

    private func inputButton(_ index: Int) -> some View {
        let selected = coordinator.selectedHDMIIndex == index + 1
        let title = coordinator.menuHDMINames[safe: index] ?? "HDMI\(index + 1)"
        return Button {
            coordinator.switchHDMIFromPanel(index: index + 1)
        } label: {
            HStack(spacing: 8) {
                Text("HDMI\(index + 1)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)

                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Image(systemName: selected ? "checkmark" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.55))
                    .frame(width: 14)
            }
            .frame(maxWidth: .infinity, minHeight: 31)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.isConnected || coordinator.isSwitchingHDMI)
        .help(title)
    }

    private var reconnectButton: some View {
        Button {
            coordinator.reconnect()
        } label: {
            Label(
                coordinator.isConnecting ? coordinator.text(.startPairing) : coordinator.text(.pairConnect),
                systemImage: coordinator.isConnecting ? "arrow.triangle.2.circlepath" : "link"
            )
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isConnecting)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.showSettings()
            } label: {
                Label(coordinator.text(.settings), systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button {
                coordinator.quit()
            } label: {
                Label(coordinator.text(.quit), systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.system(size: 11, weight: .medium))
        .buttonStyle(.borderless)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(coordinator.menuVolume) },
            set: { coordinator.setVolumeFromPanel(Int($0.rounded())) }
        )
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
        coordinator.menuMuted ? coordinator.text(.muted) : "\(coordinator.menuVolume)%"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
