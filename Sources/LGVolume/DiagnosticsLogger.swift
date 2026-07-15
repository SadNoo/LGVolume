import AppKit
import Foundation

final class DiagnosticsLogger: @unchecked Sendable {
    static let shared = DiagnosticsLogger()

    private let directoryURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let maximumBytes: UInt64

    init(
        directoryURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.codex.lgvolume/Logs", isDirectory: true),
        fileManager: FileManager = .default,
        maximumBytes: UInt64 = 512 * 1024
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.maximumBytes = maximumBytes
    }

    var logURL: URL {
        directoryURL.appendingPathComponent("LGVolume.log", isDirectory: false)
    }

    func log(_ category: String, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [\(sanitize(category))] \(sanitize(message))\n"

        lock.lock()
        defer { lock.unlock() }
        do {
            try prepareDirectory()
            try rotateIfNeeded(adding: UInt64(line.utf8.count))
            if !fileManager.fileExists(atPath: logURL.path) {
                try Data().write(to: logURL)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        } catch {
            // Diagnostics must never interrupt TV control.
        }
    }

    @MainActor
    func reveal() {
        log("diagnostics", "Log revealed by user")
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    nonisolated static func redacted(_ text: String) -> String {
        var result = text
        let patterns: [(String, String)] = [
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "<ip>"),
            (#"(?i)(client[-_ ]?key|pairing[-_ ]?token)\s*[:=]\s*[^\s,;}]+"#, "$1=<redacted>"),
            (#"(?i)\"client-key\"\s*:\s*\"[^\"]+\""#, "\"client-key\":\"<redacted>\"")
        ]
        for (pattern, replacement) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    private func sanitize(_ text: String) -> String {
        Self.redacted(text.replacingOccurrences(of: "\n", with: " "))
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    private func rotateIfNeeded(adding bytes: UInt64) throws {
        let attributes = try? fileManager.attributesOfItem(atPath: logURL.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentSize + bytes > maximumBytes else { return }

        let previousURL = directoryURL.appendingPathComponent("LGVolume.previous.log")
        try? fileManager.removeItem(at: previousURL)
        if fileManager.fileExists(atPath: logURL.path) {
            try fileManager.moveItem(at: logURL, to: previousURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: previousURL.path)
        }
    }
}
