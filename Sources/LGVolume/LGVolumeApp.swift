import SwiftUI

@main
struct LGVolumeApp: App {
    @StateObject private var coordinator: AppCoordinator

    init() {
        let coordinator = AppCoordinator()
        _coordinator = StateObject(wrappedValue: coordinator)
        NSApplication.shared.setActivationPolicy(.accessory)
        coordinator.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView(coordinator: coordinator)
                .frame(width: 184)
                .onAppear {
                    coordinator.refreshTVState()
                }
        } label: {
            Image(systemName: coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .help(coordinator.status)
        }
        .menuBarExtraStyle(.window)
    }
}
