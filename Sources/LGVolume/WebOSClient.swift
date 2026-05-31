import Foundation

struct TVVolumeStatus {
    let volume: Int
    let muted: Bool
}

final class WebOSClient: NSObject {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pending: [String: (Any) -> Bool] = [:]
    private var nextID = 1
    private var connectTimeout: DispatchWorkItem?
    private var completionCalled = false

    private(set) var isConnected = false

    func connect(ip: String, clientKey: String, forcePairing: Bool, completion: @escaping (LGResult<String>) -> Void) {
        disconnect()

        guard Self.isLocalNetworkIPv4(ip) else {
            completion(.failure("为保护隐私，LGVolume 仅允许连接局域网 IPv4 地址（例如 192.168.x.x、10.x.x.x 或 172.16-31.x.x）。"))
            return
        }

        let urls = [
            URL(string: "wss://\(ip):3001"),
            URL(string: "ws://\(ip):3000")
        ].compactMap { $0 }

        guard !urls.isEmpty else {
            completion(.failure("IP 地址无效：\(ip)"))
            return
        }

        connect(urls: urls, index: 0, ip: ip, clientKey: clientKey, forcePairing: forcePairing, completion: completion)
    }

    private func connect(urls: [URL], index: Int, ip: String, clientKey: String, forcePairing: Bool, completion: @escaping (LGResult<String>) -> Void) {
        guard urls.indices.contains(index) else {
            completion(.failure("""
            电视没有响应配对请求。

            请确认：
            1. LG C2 已开机，Mac 和电视在同一个 Wi-Fi/局域网。
            2. 电视设置里允许手机/外部 App 控制。
            3. macOS 系统设置 -> 隐私与安全性 -> 本地网络，允许 LGVolume。
            4. 如果自动扫描不准，请在电视网络设置里查看 IP 后手动填写。

            已尝试：wss://\(ip):3001 和 ws://\(ip):3000
            """))
            return
        }

        let url = urls[index]
        disconnect(keepCallbacks: true)
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
        receiveLoop()

        let id = makeID()
        var payload = registrationPayload(forcePairing: forcePairing)
        if !clientKey.isEmpty && !forcePairing {
            payload["client-key"] = clientKey
        }

        pending[id] = { response in
            guard let dictionary = response as? [String: Any] else {
                self.connectTimeout?.cancel()
                self.completionCalled = true
                completion(.failure("电视返回了无法解析的配对响应。"))
                return true
            }

            let type = dictionary["type"] as? String ?? ""
            let payload = dictionary["payload"] as? [String: Any] ?? [:]
            if type == "registered" {
                self.connectTimeout?.cancel()
                self.completionCalled = true
                self.isConnected = true
                let newKey = payload["client-key"] as? String ?? clientKey
                completion(.success(newKey))
                return true
            } else if type == "error" {
                self.connectTimeout?.cancel()
                self.completionCalled = true
                completion(.failure(payload["error"] as? String ?? "配对失败，请在电视上允许 LGVolume。"))
                return true
            } else if self.isPairingPromptResponse(type: type, payload: payload) {
                self.scheduleTimeout(after: 90) { [weak self] in
                    self?.completionCalled = true
                    completion(.failure("等待电视授权超时。请重新点“配对/连接”，并在电视弹窗出现后选择允许。"))
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

        scheduleTimeout(after: 5) { [weak self] in
            guard let self, !self.completionCalled else { return }
            self.connect(urls: urls, index: index + 1, ip: ip, clientKey: clientKey, forcePairing: forcePairing, completion: completion)
        }
    }

    func disconnect() {
        disconnect(keepCallbacks: false)
    }

    private func disconnect(keepCallbacks: Bool) {
        isConnected = false
        if !keepCallbacks {
            pending.removeAll()
        }
        connectTimeout?.cancel()
        connectTimeout = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
    }

    func getVolume(completion: @escaping (LGResult<TVVolumeStatus>) -> Void) {
        request(uri: "ssap://audio/getVolume", payload: [:]) { response in
            guard let payload = response["payload"] as? [String: Any] else {
                completion(.failure("无法读取电视音量。"))
                return
            }
            completion(.success(Self.parseVolumeStatus(payload)))
        }
    }

    func setVolume(_ volume: Int, completion: @escaping (LGResult<Void>) -> Void) {
        request(uri: "ssap://audio/setVolume", payload: ["volume": min(max(volume, 0), 100)]) { response in
            completion(Self.resultFromResponse(response))
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
            completion(Self.resultFromResponse(response))
        }
    }

    func switchHDMI(_ index: Int, completion: @escaping (LGResult<Void>) -> Void) {
        let inputID = "HDMI_\(min(max(index, 1), 4))"
        request(uri: "ssap://tv/switchInput", payload: ["inputId": inputID]) { response in
            completion(Self.resultFromResponse(response))
        }
    }

    private func request(uri: String, payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard isConnected else {
            completion(["type": "error", "payload": ["error": "尚未连接电视。"]])
            return
        }

        let id = makeID()
        pending[id] = { response in
            completion(response as? [String: Any] ?? [:])
            return true
        }
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
            switch Self.resultFromResponse(response) {
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

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveLoop()
            case .failure:
                self.isConnected = false
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
        }
    }

    private func makeID() -> String {
        let id = "lgvolume-\(nextID)"
        nextID += 1
        return id
    }

    private static func resultFromResponse(_ response: [String: Any]) -> LGResult<Void> {
        if response["type"] as? String == "error" {
            let payload = response["payload"] as? [String: Any]
            return .failure(payload?["error"] as? String ?? "电视拒绝了命令。")
        }
        return .success(())
    }

    private static func parseVolumeStatus(_ payload: [String: Any]) -> TVVolumeStatus {
        let volumeStatus = payload["volumeStatus"] as? [String: Any]
        let source = volumeStatus ?? payload
        let volume = source["volume"] as? Int
            ?? Int(source["volume"] as? Double ?? 50)
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
            "CONTROL_INPUT_JOYSTICK",
            "CONTROL_INPUT_MEDIA_RECORDING",
            "CONTROL_INPUT_MEDIA_PLAYBACK",
            "CONTROL_INPUT_TEXT",
            "CONTROL_MOUSE_AND_KEYBOARD",
            "CONTROL_POWER",
            "LAUNCH",
            "LAUNCH_WEBAPP",
            "READ_CURRENT_CHANNEL",
            "READ_INSTALLED_APPS",
            "READ_LGE_SDX",
            "READ_NOTIFICATIONS",
            "READ_POWER_STATE",
            "READ_RUNNING_APPS",
            "READ_TV_CURRENT_TIME",
            "WRITE_NOTIFICATION_TOAST"
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

    private static func isLocalNetworkIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        if parts[0] == 10 {
            return true
        }
        if parts[0] == 172 && (16...31).contains(parts[1]) {
            return true
        }
        if parts[0] == 192 && parts[1] == 168 {
            return true
        }
        if parts[0] == 169 && parts[1] == 254 {
            return true
        }
        return false
    }
}

extension WebOSClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
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
