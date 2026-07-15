import Foundation

protocol PairingTokenStoring {
    func read() -> String
    @discardableResult func save(_ token: String) -> Bool
    func clear()
}

final class FilePairingTokenStore: PairingTokenStoring {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.codex.lgvolume", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func read() -> String {
        guard let data = try? Data(contentsOf: tokenURL),
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear()
            return true
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            try Data(trimmed.utf8).write(to: tokenURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            return true
        } catch {
            return false
        }
    }

    func clear() {
        try? fileManager.removeItem(at: tokenURL)
    }

    private var tokenURL: URL {
        directoryURL.appendingPathComponent("webos-pairing-token", isDirectory: false)
    }
}
