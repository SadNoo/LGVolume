import Foundation

/// Decides whether the TV may be put in standby when the Mac goes to sleep.
///
/// The rule is deliberately conservative: the TV is only turned off when a fresh read of the
/// TV's foreground input positively matches the Mac's HDMI input. Any other input (a games
/// console, an app, live TV), an unreadable state, or an unknown Mac port leaves the TV alone.
enum TVSleepPolicy {
    enum Decision: Equatable {
        case turnOff
        case skip(reason: String)
    }

    static func decide(
        enabled: Bool,
        macPort: Int?,
        foregroundAppID: String?,
        inputs: [TVExternalInput]
    ) -> Decision {
        guard enabled else {
            return .skip(reason: "disabled")
        }
        guard let macPort, (1...4).contains(macPort) else {
            return .skip(reason: "mac port unknown")
        }
        guard let foregroundAppID, !foregroundAppID.isEmpty else {
            return .skip(reason: "foreground input unknown")
        }
        guard let foregroundPort = hdmiPort(forForegroundAppID: foregroundAppID, inputs: inputs) else {
            return .skip(reason: "foreground is not HDMI")
        }
        guard foregroundPort == macPort else {
            return .skip(reason: "foreground is HDMI\(foregroundPort), mac is HDMI\(macPort)")
        }
        return .turnOff
    }

    /// TV mode: a lock only counts once the TV has stayed on the Mac's input for this long, so
    /// anything that happens right after an input switch never turns the TV off.
    static let requiredStableMacInput: TimeInterval = 60

    static func macInputIsStable(since: Date?, now: Date = Date(), required: TimeInterval = requiredStableMacInput) -> Bool {
        guard let since else { return false }
        return now.timeIntervalSince(since) >= required
    }

    static func hdmiPort(forForegroundAppID appID: String, inputs: [TVExternalInput]) -> Int? {
        let lower = appID.lowercased()
        if let input = inputs.first(where: { !$0.appID.isEmpty && $0.appID.lowercased() == lower }) {
            return input.hdmiIndex
        }
        return WebOSResponseParser.hdmiIndex(in: appID)
    }
}
