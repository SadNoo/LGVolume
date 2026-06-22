import Foundation

struct TVVolumeStatus {
    let volume: Int
    let muted: Bool
}

final class WebOSClient: NSObject {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pending: [String: (Any) -> Bool] = [:]
    private var requestTimeouts: [String: DispatchWorkItem] = [:]
    private var requestCancellations: [String: () -> Void] = [:]
    private var nextID = 1
    private var connectTimeout: DispatchWorkItem?
    private var connectionAttemptFallback: (() -> Void)?
    private var completionCalled = false
    private let languageMode: () -> String
    private let connectionStateChanged: (Bool) -> Void

    private(set) var isConnected = false

    init(
        languageMode: @escaping () -> String = { "auto" },
        connectionStateChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.languageMode = languageMode
        self.connectionStateChanged = connectionStateChanged
    }

    func connect(ip: String, clientKey: String, forcePairing: Bool, completion: @escaping (LGResult<String>) -> Void) {
        disconnect()

        guard LocalNetworkAddress.isAllowedIPv4(ip) else {
            completion(.failure(t(.localNetworkOnly)))
            return
        }

        let urls = [
            URL(string: "wss://\(ip):3001"),
            URL(string: "ws://\(ip):3000")
        ].compactMap { $0 }

        guard !urls.isEmpty else {
            completion(.failure("\(t(.invalidIPAddress)): \(ip)"))
            return
        }

        connect(urls: urls, index: 0, ip: ip, clientKey: clientKey, forcePairing: forcePairing, completion: completion)
    }

    private func connect(urls: [URL], index: Int, ip: String, clientKey: String, forcePairing: Bool, completion: @escaping (LGResult<String>) -> Void) {
        guard urls.indices.contains(index) else {
            disconnect()
            completion(.failure(t(.tvNoResponse)))
            return
        }

        let url = urls[index]
        disconnect()
        completionCalled = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.webSocket = task
        task.resume()
        receiveLoop(for: task)
        connectionAttemptFallback = { [weak self] in
            self?.connect(
                urls: urls,
                index: index + 1,
                ip: ip,
                clientKey: clientKey,
                forcePairing: forcePairing,
                completion: completion
            )
        }

        let id = makeID()
        var payload = registrationPayload(forcePairing: forcePairing)
        if !clientKey.isEmpty && !forcePairing {
            payload["client-key"] = clientKey
        }

        pending[id] = { response in
            guard let dictionary = response as? [String: Any] else {
                self.finishConnection(.failure(self.t(.pairingResponseInvalid)), completion: completion)
                return true
            }

            let type = dictionary["type"] as? String ?? ""
            let payload = dictionary["payload"] as? [String: Any] ?? [:]
            if type == "registered" {
                self.connectTimeout?.cancel()
                self.connectionAttemptFallback = nil
                self.completionCalled = true
                self.setConnected(true)
                let newKey = payload["client-key"] as? String ?? clientKey
                completion(.success(newKey))
                return true
            } else if type == "error" {
                self.finishConnection(
                    .failure(payload["error"] as? String ?? self.t(.pairingFailed)),
                    completion: completion
                )
                return true
            } else if self.isPairingPromptResponse(type: type, payload: payload) {
                self.scheduleTimeout(after: 90) { [weak self] in
                    guard let self, !self.completionCalled else { return }
                    self.finishConnection(.failure(self.t(.pairingTimeout)), completion: completion)
                }
                return false
            } else {
                return false
            }
        }

        send(dictionary: [
            "id": id,
            "type": "register",
            "payload": payload
        ])

        scheduleTimeout(after: forcePairing ? 90 : 8) { [weak self] in
            guard let self, !self.completionCalled else { return }
            if forcePairing {
                self.finishConnection(.failure(self.t(.pairingTimeout)), completion: completion)
            } else {
                self.retryConnectionAttempt()
            }
        }
    }

    func disconnect() {
        setConnected(false)
        pending.removeAll()
        for timeout in requestTimeouts.values {
            timeout.cancel()
        }
        requestTimeouts.removeAll()
        let cancellations = Array(requestCancellations.values)
        requestCancellations.removeAll()
        connectTimeout?.cancel()
        connectTimeout = nil
        connectionAttemptFallback = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
        for cancel in cancellations {
            cancel()
        }
    }

    func getVolume(completion: @escaping (LGResult<TVVolumeStatus>) -> Void) {
        request(uri: "ssap://audio/getVolume", payload: [:]) { response in
            if case .failure(let message) = self.resultFromResponse(response) {
                completion(.failure(message))
                return
            }
            guard let payload = response["payload"] as? [String: Any] else {
                completion(.failure(self.t(.volumeReadFailed)))
                return
            }
            guard let status = Self.parseVolumeStatus(payload) else {
                completion(.failure(self.t(.volumeReadFailed)))
                return
            }
            completion(.success(status))
        }
    }

    func setVolume(_ volume: Int, completion: @escaping (LGResult<Void>) -> Void) {
        request(uri: "ssap://audio/setVolume", payload: ["volume": min(max(volume, 0), 100)]) { response in
            completion(self.resultFromResponse(response))
        }
    }

    func changeVolume(delta: Int, completion: @escaping (LGResult<Void>) -> Void) {
        guard delta != 0 else {
            completion(.success(()))
            return
        }

        let uri = delta > 0 ? "ssap://audio/volumeUp" : "ssap://audio/volumeDown"
        sendVolumeStep(uri: uri, remaining: min(abs(delta), 100), completion: completion)
    }

    func setMuted(_ muted: Bool, completion: @escaping (LGResult<Void>) -> Void) {
        request(uri: "ssap://audio/setMute", payload: ["mute": muted]) { response in
            completion(self.resultFromResponse(response))
        }
    }

    func switchHDMI(_ index: Int, completion: @escaping (LGResult<Void>) -> Void) {
        let safeIndex = min(max(index, 1), 4)
        let inputID = "HDMI_\(safeIndex)"
        request(uri: "ssap://tv/switchInput", payload: ["inputId": inputID]) { response in
            let result = self.resultFromResponse(response)
            if case .success = result {
                completion(result)
                return
            }
            self.request(
                uri: "ssap://system.launcher/launch",
                payload: ["id": "com.webos.app.hdmi\(safeIndex)"]
            ) { fallbackResponse in
                completion(self.resultFromResponse(fallbackResponse))
            }
        }
    }

    func getCurrentHDMI(completion: @escaping (LGResult<Int?>) -> Void) {
        request(uri: "ssap://com.webos.applicationManager/getForegroundAppInfo", payload: [:]) { response in
            if case .failure(let message) = self.resultFromResponse(response) {
                completion(.failure(message))
                return
            }
            let payload = response["payload"] as? [String: Any]
            let appID = (payload?["appId"] as? String ?? "").lowercased()
            let index = (1...4).first { appID.contains("hdmi\($0)") || appID.contains("hdmi_\($0)") }
            completion(.success(index))
        }
    }

    private func request(uri: String, payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard isConnected else {
            completion(["type": "error", "payload": ["error": t(.notConnected)]])
            return
        }

        let id = makeID()
        pending[id] = { response in
            completion(response as? [String: Any] ?? [:])
            return true
        }
        requestCancellations[id] = { [weak self] in
            guard let self else { return }
            completion(["type": "error", "payload": ["error": self.t(.notConnected)]])
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pending.removeValue(forKey: id) != nil else {
                return
            }
            self.requestTimeouts.removeValue(forKey: id)
            self.requestCancellations.removeValue(forKey: id)
            completion(["type": "error", "payload": ["error": self.t(.requestTimedOut)]])
        }
        requestTimeouts[id] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        send(dictionary: [
            "id": id,
            "type": "request",
            "uri": uri,
            "payload": payload
        ])
    }

    private func sendVolumeStep(uri: String, remaining: Int, completion: @escaping (LGResult<Void>) -> Void) {
        guard remaining > 0 else {
            completion(.success(()))
            return
        }

        request(uri: uri, payload: [:]) { response in
            switch self.resultFromResponse(response) {
            case .success:
                self.sendVolumeStep(uri: uri, remaining: remaining - 1, completion: completion)
            case .failure(let message):
                completion(.failure(message))
            }
        }
    }

    private func send(dictionary: [String: Any]) {
        guard let webSocket,
              let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocket.send(.string(text)) { _ in }
    }

    private func receiveLoop(for task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let task, self.webSocket === task else {
                    return
                }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop(for: task)
                case .failure:
                    self.handleTransportClosed()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else {
            return
        }
        guard let callback = pending[id] else {
            return
        }
        if callback(object) {
            pending.removeValue(forKey: id)
            requestTimeouts.removeValue(forKey: id)?.cancel()
            requestCancellations.removeValue(forKey: id)
        }
    }

    private func makeID() -> String {
        let id = "lgvolume-\(nextID)"
        nextID += 1
        return id
    }

    private func resultFromResponse(_ response: [String: Any]) -> LGResult<Void> {
        if response["type"] as? String == "error" {
            let payload = response["payload"] as? [String: Any]
            return .failure(payload?["error"] as? String ?? t(.commandRejected))
        }
        if let payload = response["payload"] as? [String: Any],
           payload["returnValue"] as? Bool == false {
            let message = payload["errorText"] as? String
                ?? payload["error"] as? String
                ?? t(.commandRejected)
            return .failure(message)
        }
        return .success(())
    }

    static func parseVolumeStatus(_ payload: [String: Any]) -> TVVolumeStatus? {
        let volumeStatus = payload["volumeStatus"] as? [String: Any]
        let source = volumeStatus ?? payload
        let volume = source["volume"] as? Int
            ?? (source["volume"] as? Double).map(Int.init)
            ?? Int(source["volume"] as? String ?? "")
        guard let volume else {
            return nil
        }
        let muted = source["muted"] as? Bool
            ?? source["mute"] as? Bool
            ?? source["muteStatus"] as? Bool
            ?? false
        return TVVolumeStatus(volume: min(max(volume, 0), 100), muted: muted)
    }

    private func scheduleTimeout(after seconds: TimeInterval, action: @escaping () -> Void) {
        connectTimeout?.cancel()
        let timeout = DispatchWorkItem(block: action)
        connectTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    private func t(_ key: L10n.Key) -> String {
        L10n.text(key, languageMode: languageMode())
    }

    private func setConnected(_ connected: Bool) {
        guard isConnected != connected else {
            return
        }
        isConnected = connected
        connectionStateChanged(connected)
    }

    private func handleTransportClosed() {
        if isConnected {
            disconnect()
        } else {
            retryConnectionAttempt()
        }
    }

    private func retryConnectionAttempt() {
        guard !completionCalled, let fallback = connectionAttemptFallback else {
            return
        }
        connectionAttemptFallback = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        pending.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
        fallback()
    }

    private func finishConnection(_ result: LGResult<String>, completion: @escaping (LGResult<String>) -> Void) {
        guard !completionCalled else {
            return
        }
        completionCalled = true
        connectTimeout?.cancel()
        connectionAttemptFallback = nil
        pending.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
        completion(result)
    }

    private func isPairingPromptResponse(type: String, payload: [String: Any]) -> Bool {
        if type == "response", payload["returnValue"] as? Bool == true {
            return true
        }
        if payload["pairingType"] as? String == "PROMPT" {
            return true
        }
        return false
    }

    private func registrationPayload(forcePairing: Bool) -> [String: Any] {
        let permissions = [
            "CONTROL_AUDIO",
            "CONTROL_DISPLAY",
            "CONTROL_INPUT_TV",
            "LAUNCH",
            "READ_RUNNING_APPS"
        ]

        return [
            "forcePairing": forcePairing,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "signed": [
                    "created": "20260523",
                    "appId": "local.codex.lgvolume",
                    "vendorId": "codex",
                    "localizedAppNames": ["": "LGVolume"],
                    "localizedVendorNames": ["": "Codex"],
                    "permissions": permissions,
                    "serial": "local-lgvolume"
                ],
                "permissions": permissions,
                "signatures": [
                    [
                        "signatureVersion": 1,
                        "signature": "LGVolume"
                    ]
                ]
            ]
        ]
    }

}

extension WebOSClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self, weak webSocketTask] in
            guard let self, let webSocketTask, self.webSocket === webSocketTask else {
                return
            }
            self.handleTransportClosed()
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
