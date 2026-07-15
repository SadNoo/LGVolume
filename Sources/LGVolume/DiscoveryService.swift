import Foundation
import Darwin

struct DiscoveredTV: Equatable {
    let name: String
    let ip: String
}

final class DiscoveryService {
    func scan(completion: @escaping ([DiscoveredTV]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            completion(self.performScan())
        }
    }

    private func performScan() -> [DiscoveredTV] {
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            return []
        }
        defer { close(socketFD) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let searches = [
            "urn:lge-com:device:webostv:1",
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "ssdp:all"
        ]

        for searchTarget in searches {
            sendSearch(searchTarget, socketFD: socketFD)
        }

        var devices: [DiscoveredTV] = []
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            guard let response = receiveResponse(socketFD: socketFD) else {
                continue
            }
            guard looksLikeLGTV(response.text) else {
                continue
            }
            if devices.contains(where: { $0.ip == response.ip }) {
                continue
            }
            let name = parseLocationURL(response.text)
                .flatMap { fetchFriendlyName(from: $0, expectedIP: response.ip) }
                ?? parseName(response.text)
                ?? "LG TV"
            let device = DiscoveredTV(name: name, ip: response.ip)
            devices.append(device)
        }
        return devices
    }

    private func sendSearch(_ searchTarget: String, socketFD: Int32) {
        let message = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: \(searchTarget)\r
        \r
        """

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &address.sin_addr)

        message.withCString { pointer in
            withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    _ = sendto(socketFD, pointer, strlen(pointer), 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func receiveResponse(socketFD: Int32) -> (text: String, ip: String)? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)

        let count = withUnsafeMutablePointer(to: &storage) { storagePointer in
            storagePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                recvfrom(socketFD, &buffer, buffer.count, 0, socketAddress, &length)
            }
        }

        guard count > 0 else {
            return nil
        }

        let data = Data(buffer.prefix(Int(count)))
        let text = String(data: data, encoding: .utf8) ?? ""
        let ip = ipAddress(from: storage) ?? parseLocationIP(text) ?? ""
        guard !ip.isEmpty else {
            return nil
        }
        return (text, ip)
    }

    private func ipAddress(from storage: sockaddr_storage) -> String? {
        var storage = storage
        guard storage.ss_family == sa_family_t(AF_INET) else {
            return nil
        }

        var address = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        return withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { socketAddress in
                var sinAddr = socketAddress.pointee.sin_addr
                guard inet_ntop(AF_INET, &sinAddr, &address, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: address)
            }
        }
    }

    private func looksLikeLGTV(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("webos")
            || lower.contains("urn:lge-com")
            || lower.contains("lg smart tv")
            || lower.contains("lg-electronics")
    }

    private func parseName(_ text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            if lower.hasPrefix("server:") && lower.contains("webos") {
                return "LG TV"
            }
            if lower.hasPrefix("friendlyname:") {
                return value(afterColonIn: line)
            }
        }
        return nil
    }

    private func parseLocationIP(_ text: String) -> String? {
        parseLocationURL(text)?.host
    }

    private func parseLocationURL(_ text: String) -> URL? {
        for line in text.components(separatedBy: .newlines) where line.lowercased().hasPrefix("location:") {
            guard let value = value(afterColonIn: line), let url = URL(string: value) else { continue }
            return url
        }
        return nil
    }

    private func fetchFriendlyName(from url: URL, expectedIP: String) -> String? {
        guard url.scheme?.lowercased() == "http",
              url.host == expectedIP,
              LocalNetworkAddress.isAllowedIPv4(expectedIP) else {
            return nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration)
        let semaphore = DispatchSemaphore(value: 0)
        let responseBox = HTTPResponseDataBox()
        let task = session.dataTask(with: url) { data, response, _ in
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let data,
               data.count <= 256 * 1024 {
                responseBox.store(data)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        task.cancel()
        session.invalidateAndCancel()
        guard let responseData = responseBox.value else { return nil }
        return Self.parseFriendlyName(responseData)
    }

    static func parseFriendlyName(_ data: Data) -> String? {
        let delegate = FriendlyNameXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.friendlyName
    }

    private func value(afterColonIn line: String) -> String? {
        guard let index = line.firstIndex(of: ":") else {
            return nil
        }
        let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private final class HTTPResponseDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Data?

    var value: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func store(_ data: Data) {
        lock.lock()
        storedValue = data
        lock.unlock()
    }
}

private final class FriendlyNameXMLDelegate: NSObject, XMLParserDelegate {
    private var capturesFriendlyName = false
    private var value = ""
    private(set) var friendlyName: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        capturesFriendlyName = elementName.lowercased() == "friendlyname"
        if capturesFriendlyName { value = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesFriendlyName { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName.lowercased() == "friendlyname" else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        friendlyName = trimmed.isEmpty ? nil : trimmed
        capturesFriendlyName = false
    }
}
