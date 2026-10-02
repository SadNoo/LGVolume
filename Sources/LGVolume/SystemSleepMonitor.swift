import Foundation
import IOKit
import IOKit.pwr_mgt

/// Observes system sleep and wake through IOKit power notifications.
///
/// Unlike NSWorkspace notifications, IOKit lets the app briefly hold system sleep until the
/// "will sleep" work is done (macOS waits up to 30 seconds). The handler always gets a bounded
/// time budget and sleep is acknowledged exactly once, whatever the handler does.
@MainActor
final class SystemSleepMonitor {
    typealias WillSleepHandler = (_ done: @escaping @MainActor () -> Void) -> Void

    private let willSleepTimeout: TimeInterval
    private let onWillSleep: WillSleepHandler
    private let onDidWake: () -> Void
    private var rootPort: io_connect_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init(
        willSleepTimeout: TimeInterval = 5,
        onWillSleep: @escaping WillSleepHandler,
        onDidWake: @escaping () -> Void
    ) {
        self.willSleepTimeout = willSleepTimeout
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    func start() {
        guard rootPort == 0 else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notificationPort, { context, _, messageType, argument in
            guard let context else { return }
            let monitor = Unmanaged<SystemSleepMonitor>.fromOpaque(context).takeUnretainedValue()
            let notificationID = Int(bitPattern: argument)
            MainActor.assumeIsolated {
                monitor.handle(messageType: messageType, notificationID: notificationID)
            }
        }, &notifier)
        guard rootPort != 0, let notificationPort else {
            rootPort = 0
            return
        }
        IONotificationPortSetDispatchQueue(notificationPort, .main)
    }

    private func handle(messageType: UInt32, notificationID: Int) {
        switch messageType {
        case Self.canSystemSleep:
            // Idle sleep query: never veto it.
            IOAllowPowerChange(rootPort, notificationID)
        case Self.systemWillSleep:
            var acknowledged = false
            let acknowledge: @MainActor () -> Void = { [weak self] in
                guard let self, !acknowledged else { return }
                acknowledged = true
                IOAllowPowerChange(self.rootPort, notificationID)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + willSleepTimeout) {
                acknowledge()
            }
            onWillSleep(acknowledge)
        case Self.systemHasPoweredOn:
            onDidWake()
        default:
            break
        }
    }

    // iokit_common_msg(message) == sys_iokit | sub_iokit_common | message
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300
}
