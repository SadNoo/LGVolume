import SwiftUI

struct MenuBarControlView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var sliderVolume = 50.0
    @State private var isSliding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            volumeControls
            actionList
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            SingleLayerPanelSheen()
        }
        .onAppear {
            sliderVolume = Double(coordinator.menuVolume)
        }
        .onChange(of: coordinator.menuVolume) { _, newValue in
            guard !isSliding else { return }
            sliderVolume = Double(newValue)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(headerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(coordinator.isConnected ? .primary : .secondary)
                .lineLimit(1)

            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
                }
                .accessibilityLabel(coordinator.isConnected ? coordinator.text(.connected) : coordinator.text(.currentDisconnected))

            Spacer(minLength: 8)
        }
    }

    private var volumeControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Button {
                    coordinator.toggleMuteFromPanel()
                } label: {
                    Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(coordinator.menuMuted ? coordinator.text(.turnMuteOff) : coordinator.text(.turnMuteOn))

                Text(coordinator.text(.volume))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(displayVolumeText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }

            HStack(spacing: 6) {
                Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                VolumeTrack(
                    value: $sliderVolume,
                    disabled: coordinator.menuMuted,
                    onEditingChanged: { editing in
                        isSliding = editing
                        if !editing {
                            coordinator.setVolumeFromPanel(Int(sliderVolume.rounded()))
                        }
                    }
                )

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .controlSize(.mini)
        }
    }

    private var actionList: some View {
        VStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { index in
                Button {
                    coordinator.switchHDMIFromPanel(index: index + 1)
                } label: {
                    HDMIButtonLabel(
                        title: coordinator.menuHDMINames[safe: index] ?? "HDMI\(index + 1)",
                        isSelected: coordinator.selectedHDMIIndex == index + 1
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                coordinator.showSettings()
            } label: {
                FooterActionLabel(title: coordinator.text(.settings))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Button {
                coordinator.quit()
            } label: {
                FooterActionLabel(title: coordinator.text(.quit))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var headerTitle: String {
        if coordinator.isConnected {
            return coordinator.menuTitle
        }
        return coordinator.text(.currentDisconnected)
    }

    private var statusColor: Color {
        coordinator.isConnected ? .green : .secondary.opacity(0.55)
    }

    private var displayVolumeText: String {
        if coordinator.menuMuted {
            return coordinator.text(.muted)
        }
        let value = isSliding ? Int(sliderVolume.rounded()) : coordinator.menuVolume
        return "\(value)%"
    }
}

private struct HDMIButtonLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 27)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.12 : 0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.72) : Color.primary.opacity(0.10), lineWidth: isSelected ? 1.2 : 0.7)
        }
    }
}

private struct FooterActionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
            }
    }
}

private struct VolumeTrack: View {
    @Binding var value: Double
    let disabled: Bool
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = CGFloat(min(max(value / 100, 0), 1))
            let thumbSize: CGFloat = 13
            let thumbX = min(max(progress * width, thumbSize / 2), width - thumbSize / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(disabled ? 0.13 : 0.16))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.primary.opacity(disabled ? 0.18 : 0.78))
                    .frame(width: max(thumbX, 0), height: 4)

                Circle()
                    .fill(disabled ? Color.secondary.opacity(0.48) : Color.primary.opacity(0.94))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard !disabled else { return }
                        onEditingChanged(true)
                        let raw = min(max(gesture.location.x / width, 0), 1)
                        value = Double(raw * 100).rounded()
                    }
                    .onEnded { gesture in
                        guard !disabled else { return }
                        let raw = min(max(gesture.location.x / width, 0), 1)
                        value = Double(raw * 100).rounded()
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 18)
        .opacity(disabled ? 0.62 : 1)
    }
}

private struct SingleLayerPanelSheen: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.055), Color.clear]
                    : [Color.white.opacity(0.18), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
