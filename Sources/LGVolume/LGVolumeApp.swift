import SwiftUI

@main
struct LGVolumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and panel are AppKit (StatusItemController). SwiftUI still needs a
        // scene; an uninserted MenuBarExtra adds no window, menu item or status item.
        MenuBarExtra("LGVolume", systemImage: "tv", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        statusItemController = StatusItemController(coordinator: coordinator)
        coordinator.start()
    }
}
