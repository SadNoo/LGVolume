import Foundation

/// Decides when "the Mac stopped sending a picture to the TV" really means the Mac went to sleep.
///
/// On an LG C2, switching the TV's input (to a Switch 2 and back, by remote or hotkey) makes
/// macOS report the display as turned off for a few seconds; observed blips lasted 0-38 s, while
/// a real display sleep lasts from tens of minutes to hours. The gate therefore fires only after
/// the display has stayed off for `delay` without waking and without the TV changing input.
@MainActor
final class DisplayOffStandbyGate {
    typealias Schedule = (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void

    nonisolated static let defaultDelay: TimeInterval = 60

    private let delay: TimeInterval
    private let schedule: Schedule
    private let onElapsed: () -> Void
    private let log: (String) -> Void
    private var cancelPending: (() -> Void)?
    private var displayOffSince: Date?

    init(
        delay: TimeInterval = DisplayOffStandbyGate.defaultDelay,
        schedule: @escaping Schedule = DisplayOffStandbyGate.dispatchSchedule,
        log: @escaping (String) -> Void = { _ in },
        onElapsed: @escaping () -> Void
    ) {
        self.delay = delay
        self.schedule = schedule
        self.log = log
        self.onElapsed = onElapsed
    }

    var isWaiting: Bool { cancelPending != nil }

    func displaysDidSleep() {
        guard displayOffSince == nil else { return }
        displayOffSince = Date()
        log("display off: waiting \(Int(delay)) s before considering TV standby")
        cancelPending = schedule(delay) { [weak self] in
            guard let self, self.displayOffSince != nil else { return }
            self.cancelPending = nil
            self.log("display stayed off for \(Int(self.delay)) s")
            self.onElapsed()
        }
    }

    func displaysDidWake() {
        if let since = displayOffSince, isWaiting {
            log("display back on after \(Int(Date().timeIntervalSince(since))) s: no standby")
        }
        reset()
    }

    /// The TV switched input while the display was off: that was an input switch, not sleep.
    func tvInputChanged() {
        guard isWaiting else { return }
        log("TV input changed while display was off: no standby")
        cancelPending?()
        cancelPending = nil
    }

    func reset() {
        cancelPending?()
        cancelPending = nil
        displayOffSince = nil
    }

    nonisolated static let dispatchSchedule: Schedule = { delay, action in
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
