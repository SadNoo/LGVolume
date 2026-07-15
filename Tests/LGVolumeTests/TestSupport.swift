import Foundation
@testable import LGVolume

final class MemoryPairingTokenStore: PairingTokenStoring {
    var token = ""
    var savesSuccessfully = true

    func read() -> String { token }

    func save(_ token: String) -> Bool {
        guard savesSuccessfully else { return false }
        self.token = token
        return true
    }

    func clear() {
        token = ""
    }
}

final class MemoryServerTrustStorage: ServerTrustStorage {
    private var values: [String: String] = [:]
    var savesSuccessfully = true

    func fingerprint(for host: String) -> String {
        values[host] ?? ""
    }

    func saveFingerprint(_ fingerprint: String, for host: String) -> Bool {
        guard savesSuccessfully else { return false }
        values[host] = fingerprint
        return true
    }

    func clearFingerprint(for host: String) {
        values.removeValue(forKey: host)
    }
}
