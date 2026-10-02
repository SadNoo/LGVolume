import SwiftUI

private extension AppCoordinator {
    var inputsDisabled: Bool { !isConnected || isSwitchingHDMI }

    var connectionSubtitle: String {
        if isConnecting { return text(.connecting) }
        guard isConnected else { return text(.currentDisconnected) }
        return selectedInputName.map { "\(text(.nowShowing)) \($0)" } ?? text(.connected)
    }
}

private struct InputCaption: View {
    var input: PanelInput
    var coordinator: AppCoordinator
    var showsShortcut = true

    var body: some View {
        HStack(spacing: 0) {
            Text("HDMI\(input.index)")
            if !input.isPresent {
                Text("  ·  \(coordinator.text(.inputNotConnected))")
            } else if showsShortcut, let shortcut = input.shortcut {
                Text("  ·  \(shortcut)")
            }
        }
        .lineLimit(1)
    }
}

// MARK: - Input cards (default)

struct CardsMenuPanel: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(coordinator.menuTitle).font(.system(size: 15, weight: .bold)).lineLimit(1)
                StatusIndicator(coordinator: coordinator)
                Spacer(minLength: 8)
                Text(coordinator.connectionSubtitle)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .padding(.bottom, 2)

            ConnectionBanner(coordinator: coordinator)

            ForEach(PanelInput.all(from: coordinator)) { input in
                Button {
                    coordinator.switchHDMIFromPanel(index: input.index)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: input.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(input.isSelected ? Color.white : Color.primary.opacity(0.75))
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 9).fill(input.isSelected ? Color.accentColor : Color.primary.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(input.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                if input.isMac { MacBadge() }
                            }
                            InputCaption(input: input, coordinator: coordinator)
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if input.isSelected {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(input.isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(input.isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
                    .hoverHighlight(cornerRadius: 11, enabled: !coordinator.inputsDisabled && !input.isSelected)
                    .contentShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .opacity(input.isPresent ? 1 : 0.6)
                .help(input.name)
            }
            .disabled(coordinator.inputsDisabled)
            .opacity(coordinator.isConnected ? 1 : 0.45)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    PanelMuteButton(coordinator: coordinator, size: 18, filled: false)
                    PanelVolumeBar(coordinator: coordinator, thickness: 6)
                    PanelVolumeText(coordinator: coordinator, font: .system(size: 12, weight: .semibold))
                        .frame(width: 40, alignment: .trailing)
                }
                Divider().opacity(0.6)
                SoundOutputButton(coordinator: coordinator) {
                    HStack(spacing: 6) {
                        Image(systemName: "hifispeaker").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                        Text(coordinator.text(.soundOutput)).font(.system(size: 12))
                        Spacer()
                        Text(coordinator.soundOutputValueText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
                SleepSyncRow(coordinator: coordinator)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.05)))
            .padding(.top, 2)

            PanelFooter(coordinator: coordinator)
                .padding(.horizontal, 4).padding(.top, 2)
        }
        .padding(12)
    }
}

// MARK: - Native sections

struct NativeMenuPanel: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconCircle(symbol: "tv", active: coordinator.isConnected, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(coordinator.menuTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(coordinator.connectionSubtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                PanelVolumeText(coordinator: coordinator, font: .system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)

            ConnectionBanner(coordinator: coordinator)
                .padding(.horizontal, 10).padding(.bottom, 8)

            section(coordinator.text(.volume))
            HStack(spacing: 9) {
                PanelMuteButton(coordinator: coordinator)
                PanelVolumeBar(coordinator: coordinator, thickness: 5)
            }
            .padding(.horizontal, 14).padding(.bottom, 8)

            divider
            section(coordinator.text(.inputSources))
            ForEach(PanelInput.all(from: coordinator)) { input in
                Button {
                    coordinator.switchHDMIFromPanel(index: input.index)
                } label: {
                    HStack(spacing: 9) {
                        IconCircle(symbol: input.symbol, active: input.isSelected, size: 26)
                        Text(input.name).font(.system(size: 13, weight: input.isSelected ? .semibold : .regular)).lineLimit(1)
                        Spacer(minLength: 4)
                        if input.isMac { MacBadge() }
                        if let shortcut = input.shortcut {
                            Text(shortcut).font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .hoverHighlight(enabled: !coordinator.inputsDisabled)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .opacity(input.isPresent ? 1 : 0.6)
            }
            .disabled(coordinator.inputsDisabled)
            .opacity(coordinator.isConnected ? 1 : 0.45)

            divider
            section(coordinator.text(.soundOutput))
            SoundOutputButton(coordinator: coordinator) {
                HStack(spacing: 9) {
                    IconCircle(symbol: "hifispeaker", active: false, size: 26)
                    Text(coordinator.soundOutputValueText).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .hoverHighlight()
            }
            .padding(.horizontal, 6)

            divider
            SleepSyncRow(coordinator: coordinator, showsIcon: false, fontSize: 13)
                .padding(.horizontal, 14).padding(.vertical, 4)
            divider
            menuRow(coordinator.text(.settingsEllipsis), key: "⌘,") { coordinator.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
            menuRow(coordinator.text(.quitApp), key: "⌘Q") { coordinator.quit() }
                .keyboardShortcut("q", modifiers: .command)
                .padding(.bottom, 6)
        }
    }

    private var divider: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 4)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 5)
    }

    private func menuRow(_ title: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(key).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .hoverHighlight()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

// MARK: - Control Center modules

struct ControlCenterMenuPanel: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PanelModule {
                    HStack(spacing: 10) {
                        IconCircle(symbol: "tv", active: coordinator.isConnected, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(coordinator.menuTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(coordinator.connectionSubtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Button {
                    coordinator.setSleepTVWithMac(!coordinator.sleepTVWithMac)
                } label: {
                    PanelModule {
                        VStack(spacing: 4) {
                            IconCircle(symbol: "moon.zzz.fill", active: coordinator.sleepTVWithMac, size: 32)
                            Text(coordinator.sleepTVNeedsRepair ? coordinator.text(.needsRepairShort) : coordinator.text(.sleepTVShort))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(coordinator.sleepTVNeedsRepair ? Color.orange : Color.primary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 92)
                .help(coordinator.text(.sleepTVWithMacHelp))
            }

            ConnectionBanner(coordinator: coordinator)

            PanelModule {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(coordinator.text(.volume)).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        PanelVolumeText(coordinator: coordinator, font: .system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    PanelVolumeBar(coordinator: coordinator, thickness: 26, prominent: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(PanelInput.all(from: coordinator)) { input in
                    Button {
                        coordinator.switchHDMIFromPanel(index: input.index)
                    } label: {
                        PanelModule(padding: 9) {
                            HStack(spacing: 8) {
                                IconCircle(symbol: input.symbol, active: input.isSelected, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(input.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(input.isPresent ? "HDMI\(input.index)" : coordinator.text(.inputNotConnected))
                                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        if input.isMac { MacBadge() }
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(input.shortcut.map { "\(input.name)  \($0)" } ?? input.name)
                }
            }
            .disabled(coordinator.inputsDisabled)
            .opacity(coordinator.isConnected ? 1 : 0.45)

            SoundOutputButton(coordinator: coordinator) {
                PanelModule {
                    HStack(spacing: 10) {
                        IconCircle(symbol: "hifispeaker.fill", active: false, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(coordinator.text(.soundOutput)).font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(coordinator.soundOutputValueText).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
            }

            PanelFooter(coordinator: coordinator)
                .padding(.horizontal, 4)
        }
        .padding(12)
    }
}

// MARK: - Compact bar

struct CompactMenuPanel: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                StatusIndicator(coordinator: coordinator)
                Text(coordinator.isConnected ? coordinator.menuTitle : coordinator.connectionSubtitle)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(coordinator.isConnected ? (coordinator.menuMuted ? coordinator.text(.muted) : "\(coordinator.menuVolume)") : "—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }

            ConnectionBanner(coordinator: coordinator, showsActions: true)

            HStack(spacing: 8) {
                PanelMuteButton(coordinator: coordinator, size: 18, filled: false)
                PanelVolumeBar(coordinator: coordinator, thickness: 6)
            }

            HStack(spacing: 5) {
                ForEach(PanelInput.all(from: coordinator)) { input in
                    Button {
                        coordinator.switchHDMIFromPanel(index: input.index)
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: input.symbol).font(.system(size: 15, weight: .medium))
                                    .frame(width: 30, height: 20)
                                if input.isMac {
                                    Circle().fill(Color.green).frame(width: 5, height: 5).offset(x: 1, y: -1)
                                }
                            }
                            Text(input.name).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(input.isSelected ? Color.white : Color.primary.opacity(0.8))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(input.isSelected ? Color.accentColor : Color.primary.opacity(0.07)))
                        .hoverHighlight(cornerRadius: 8, enabled: !input.isSelected)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .opacity(input.isPresent ? 1 : 0.6)
                    .help(input.shortcut.map { "\(input.name) · HDMI\(input.index)  \($0)" } ?? "\(input.name) · HDMI\(input.index)")
                }
            }
            .disabled(coordinator.inputsDisabled)
            .opacity(coordinator.isConnected ? 1 : 0.45)

            HStack(spacing: 12) {
                SoundOutputButton(coordinator: coordinator) {
                    HStack(spacing: 4) {
                        Image(systemName: "hifispeaker").font(.system(size: 10))
                        Text(coordinator.currentSoundOutputTitle).font(.system(size: 11)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    coordinator.setSleepTVWithMac(!coordinator.sleepTVWithMac)
                } label: {
                    Image(systemName: coordinator.sleepTVWithMac ? "moon.zzz.fill" : "moon.zzz")
                        .foregroundStyle(coordinator.sleepTVNeedsRepair ? Color.orange : (coordinator.sleepTVWithMac ? Color.accentColor : Color.secondary))
                }
                .buttonStyle(.plain)
                .help("\(coordinator.text(.sleepTVShort))\(coordinator.sleepTVNeedsRepair ? " · \(coordinator.text(.needsRepairShort))" : "")")
                .accessibilityLabel(coordinator.text(.sleepTVShort))
                PanelFooter(coordinator: coordinator, iconsOnly: true)
            }
            .font(.system(size: 12))
        }
        .padding(13)
    }
}

// MARK: - Two-column remote

struct RemoteMenuPanel: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                StatusIndicator(coordinator: coordinator)
                Text(coordinator.isConnected ? coordinator.menuTitle : coordinator.connectionSubtitle)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Button {
                    coordinator.setSleepTVWithMac(!coordinator.sleepTVWithMac)
                } label: {
                    Image(systemName: coordinator.sleepTVWithMac ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 12))
                        .foregroundStyle(coordinator.sleepTVNeedsRepair ? Color.orange : (coordinator.sleepTVWithMac ? Color.accentColor : Color.secondary))
                }
                .buttonStyle(.plain)
                .help("\(coordinator.text(.sleepTVShort))\(coordinator.sleepTVNeedsRepair ? " · \(coordinator.text(.needsRepairShort))" : "")")
                .accessibilityLabel(coordinator.text(.sleepTVShort))
            }

            ConnectionBanner(coordinator: coordinator)

            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 6) {
                    Text(coordinator.isConnected ? (coordinator.menuMuted ? coordinator.text(.muted) : "\(coordinator.menuVolume)") : "—")
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    PanelVolumeBar(coordinator: coordinator, thickness: 64, vertical: true, prominent: true)
                }
                .frame(width: 64, height: 214)

                VStack(spacing: 5) {
                    ForEach(PanelInput.all(from: coordinator)) { input in
                        Button {
                            coordinator.switchHDMIFromPanel(index: input.index)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: input.symbol).font(.system(size: 13, weight: .medium)).frame(width: 20)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(input.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(input.isPresent ? "HDMI\(input.index)" : coordinator.text(.inputNotConnected))
                                        .font(.system(size: 9.5)).opacity(0.7).lineLimit(1)
                                }
                                Spacer(minLength: 2)
                                if input.isMac { MacBadge() }
                            }
                            .foregroundStyle(input.isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 9).frame(height: 39)
                            .background(RoundedRectangle(cornerRadius: 10).fill(input.isSelected ? Color.accentColor : Color.primary.opacity(0.07)))
                            .hoverHighlight(cornerRadius: 10, enabled: !input.isSelected)
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .opacity(input.isPresent ? 1 : 0.6)
                        .help(input.shortcut.map { "\(input.name)  \($0)" } ?? input.name)
                    }
                    .disabled(coordinator.inputsDisabled)
                    .opacity(coordinator.isConnected ? 1 : 0.45)

                    SoundOutputButton(coordinator: coordinator) {
                        HStack(spacing: 6) {
                            Image(systemName: "hifispeaker").font(.system(size: 11))
                            Text(coordinator.currentSoundOutputTitle).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
                    }
                }
            }

            Divider()
            PanelFooter(coordinator: coordinator)
        }
        .padding(13)
    }
}

/// Green when connected, orange while connecting, grey otherwise.
struct StatusIndicator: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Circle()
            .fill(coordinator.isConnecting ? Color.orange : (coordinator.isConnected ? Color.green : Color.secondary.opacity(0.5)))
            .frame(width: 7, height: 7)
            .accessibilityLabel(coordinator.isConnected ? coordinator.text(.connected) : coordinator.text(.currentDisconnected))
    }
}
