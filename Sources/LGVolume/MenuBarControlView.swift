import SwiftUI

struct MenuBarControlView: View {
    @ObservedObject var coordinator: AppCoordinator

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            volumeControls
            hdmiGrid
            footer
        }
        .padding(20)
        .background {
            LiquidGlassBackground()
        }
        .padding(8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(coordinator.menuTitle)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Text(coordinator.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var volumeControls: some View {
        HStack(spacing: 10) {
            Button {
                coordinator.toggleMuteFromPanel()
            } label: {
                Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(coordinator.menuMuted ? "取消静音" : "静音")

            Text("音量")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(coordinator.menuMuted ? "静音" : "\(coordinator.menuVolume)%")
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())

            HStack(spacing: 6) {
                Button {
                    coordinator.adjustVolumeFromPanel(delta: -1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                }

                Button {
                    coordinator.adjustVolumeFromPanel(delta: 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var hdmiGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                Button {
                    coordinator.switchHDMIFromPanel(index: index + 1)
                } label: {
                    Text(coordinator.menuHDMINames[safe: index] ?? "HDMI\(index + 1)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("设置") {
                coordinator.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("退出") {
                coordinator.quit()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

private struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                liquidTint
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.46))
                    .frame(height: 24)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.74), lineWidth: 0.8)
                    .padding(1.2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.18), radius: 24, y: 12)
    }

    private var liquidTint: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.12), Color.black.opacity(0.10)]
                : [Color.white.opacity(0.42), Color.white.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
