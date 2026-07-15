import CryptoKit
import Foundation
import Security

protocol ServerTrustStorage {
    func fingerprint(for host: String) -> String
    @discardableResult func saveFingerprint(_ fingerprint: String, for host: String) -> Bool
    func clearFingerprint(for host: String)
}

final class DefaultsServerTrustStorage: ServerTrustStorage {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = UserDefaults(suiteName: "local.codex.lgvolume") ?? .standard,
        key: String = "webosCertificateFingerprints"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func fingerprint(for host: String) -> String {
        fingerprints[host] ?? ""
    }

    @discardableResult
    func saveFingerprint(_ fingerprint: String, for host: String) -> Bool {
        var values = fingerprints
        values[host] = fingerprint
        defaults.set(values, forKey: key)
        return defaults.dictionary(forKey: key)?[host] as? String == fingerprint
    }

    func clearFingerprint(for host: String) {
        var values = fingerprints
        values.removeValue(forKey: host)
        defaults.set(values, forKey: key)
    }

    private var fingerprints: [String: String] {
        defaults.dictionary(forKey: key)?.compactMapValues { $0 as? String } ?? [:]
    }
}

final class ServerTrustValidator: @unchecked Sendable {
    enum Failure {
        case certificateChanged
        case fingerprintSaveFailed
    }

    private let storage: ServerTrustStorage
    private let lock = NSLock()
    private var failures: [String: Failure] = [:]

    init(storage: ServerTrustStorage = DefaultsServerTrustStorage()) {
        self.storage = storage
    }

    func evaluate(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.port == 3001,
              LocalNetworkAddress.isAllowedIPv4(space.host),
              let trust = space.serverTrust,
              let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificateChain.first else {
            return (.performDefaultHandling, nil)
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: certificateData).map { String(format: "%02x", $0) }.joined()
        let saved = storage.fingerprint(for: space.host)

        if saved.isEmpty {
            guard storage.saveFingerprint(fingerprint, for: space.host) else {
                record(.fingerprintSaveFailed, host: space.host)
                return (.cancelAuthenticationChallenge, nil)
            }
        } else if saved != fingerprint {
            record(.certificateChanged, host: space.host)
            return (.cancelAuthenticationChallenge, nil)
        }

        return (.useCredential, URLCredential(trust: trust))
    }

    func consumeFailure(for host: String) -> Failure? {
        lock.lock()
        defer { lock.unlock() }
        return failures.removeValue(forKey: host)
    }

    func clearFingerprint(for host: String) {
        storage.clearFingerprint(for: host)
        lock.lock()
        failures.removeValue(forKey: host)
        lock.unlock()
    }

    private func record(_ failure: Failure, host: String) {
        lock.lock()
        failures[host] = failure
        lock.unlock()
    }
}
