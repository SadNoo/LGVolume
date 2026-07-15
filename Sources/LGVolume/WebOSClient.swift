import Foundation

@MainActor
final class WebOSClient: NSObject {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pending: [String: (Any) -> Bool] = [:]
    private var subscriptionIDs: Set<String> = []
    private var requestTimeouts: [String: DispatchWorkItem] = [:]
    private var requestCancellations: [String: (String) -> Void] = [:]
    private var nextID = 1
    private var connectTimeout: DispatchWorkItem?
    private var connectionAttemptFallback: (() -> Void)?
    private var connectionFailureHandler: ((String) -> Void)?
    private var currentConnectionHost = ""
    private var completionCalled = false
    private let languageMode: () -> String
    private let connectionStateChanged: (Bool) -> Void
    private let logger: DiagnosticsLogger
    nonisolated private let trustValidator: ServerTrustValidator

    private(set) var isConnected = false

    init(
        languageMode: @escaping () -> String = { "auto" },
        connectionStateChanged: @escaping (Bool) -> Void = { _ in },
        trustValidator: ServerTrustValidator = ServerTrustValidator(),
        logger: DiagnosticsLogger = .shared
    ) {
        self.languageMode = languageMode
        self.connectionStateChanged = connectionStateChanged
        self.trustValidator = trustValidator
        self.logger = logger
    }

    func connect(
        ip: String,
        clientKey: String,
        forcePairing: Bool,
        secureConnectionOnly: Bool = false,
        completion: @escaping (LGResult<String>) -> Void
    ) {
        disconnect()

        guard LocalNetworkAddress.isAllowedIPv4(ip) else {
            completion(.failure(t(.localNetworkOnly)))
            return
        }

        _ = trustValidator.consumeFailure(for: ip)
        var urls = [URL(string: "wss://\(ip):3001")].compactMap { $0 }
        if !secureConnectionOnly, let fallbackURL = URL(string: "ws://\(ip):3000") {
            urls.append(fallbackURL)
        }

        guard !urls.isEmpty else {
            completion(.failure("\(t(.invalidIPAddress)): \(ip)"))
            return
        }

        connect(urls: urls, index: 0, ip: ip, clientKey: clientKey, forcePairing: forcePairing, completion: completion)
    }

    func forgetServerTrust(ip: String) {
        guard LocalNetworkAddress.isAllowedIPv4(ip) else { return }
        trustValidator.clearFingerprint(for: ip)
    }

    private func connect(
        urls: [URL],
        index: Int,
        ip: String,
        clientKey: String,
        forcePairing: Bool,
        completion: @escaping (LGResult<String>) -> Void
    ) {
        guard urls.indices.contains(index) else {
            disconnect()
            completion(.failure(t(.tvNoResponse)))
            return
        }

        let url = urls[index]
        disconnect()
        completionCalled = false
        currentConnectionHost = ip
        connectionFailureHandler = { [weak self] message in
            self?.finishConnection(.failure(message), completion: completion)
        }

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
        var payload = WebOSRegistration.payload(forcePairing: forcePairing)
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
                self.connectionFailureHandler = nil
                self.completionCalled = true
                self.setConnected(true)
                let newKey = payload["client-key"] as? String ?? clientKey
                completion(.success(newKey))
                return true
            }
            if type == "error" {
                self.finishConnection(
                    .failure(payload["error"] as? String ?? dictionary["error"] as? String ?? self.t(.pairingFailed)),
                    completion: completion
                )
                return true
            }
            if self.isPairingPromptResponse(type: type, payload: payload) {
                self.scheduleTimeout(after: 90) { [weak self] in
                    guard let self, !self.completionCalled else { return }
                    self.finishConnection(.failure(self.t(.pairingTimeout)), completion: completion)
                }
                return false
            }
            return false
        }

        send(dictionary: [
            "id": id,
            "type": "register",
            "payload": payload
        ]) { [weak self] in
            guard let self, !self.completionCalled else { return }
            if forcePairing {
                self.finishConnection(.failure(self.t(.sendFailed)), completion: completion)
            } else {
                self.retryConnectionAttempt()
            }
        }

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
        subscriptionIDs.removeAll()
        for timeout in requestTimeouts.values {
            timeout.cancel()
        }
        requestTimeouts.removeAll()
        let cancellations = Array(requestCancellations.values)
        requestCancellations.removeAll()
        connectTimeout?.cancel()
        connectTimeout = nil
        connectionAttemptFallback = nil
        connectionFailureHandler = nil
        currentConnectionHost = ""
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        for cancel in cancellations {
            cancel(t(.notConnected))
        }
    }

    func getVolume(completion: @escaping (LGResult<TVVolumeStatus>) -> Void) {
        request(uri: "ssap://audio/getVolume", payload: [:]) { response in
            completion(self.volumeResult(from: response))
        }
    }

    func subscribeVolume(_ completion: @escaping (LGResult<TVVolumeStatus>) -> Void) {
        subscribe(uri: "ssap://audio/getVolume", payload: [:]) { response in
            completion(self.volumeResult(from: response))
        }
    }

    func getMuted(completion: @escaping (LGResult<Bool>) -> Void) {
        request(uri: "ssap://audio/getStatus", payload: [:]) { response in
            let result = self.muteResult(from: response)
            guard case .failure = result else {
                completion(result)
                return
            }
            self.request(uri: "ssap://audio/getMute", payload: [:]) { fallbackResponse in
                completion(self.muteResult(from: fallbackResponse))
            }
        }
    }

    func subscribeMuted(_ completion: @escaping (LGResult<Bool>) -> Void) {
        var startedFallback = false
        subscribe(uri: "ssap://audio/getStatus", payload: [:]) { response in
            let result = self.muteResult(from: response)
            if case .failure = result, !startedFallback {
                startedFallback = true
                self.subscribe(uri: "ssap://audio/getMute", payload: [:]) { fallbackResponse in
                    completion(self.muteResult(from: fallbackResponse))
                }
                return
            }
            completion(result)
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

    func getExternalInputs(completion: @escaping (LGResult<[TVExternalInput]>) -> Void) {
        request(uri: "ssap://tv/getExternalInputList", payload: [:]) { response in
            completion(self.externalInputsResult(from: response))
        }
    }

    func subscribeExternalInputs(_ completion: @escaping (LGResult<[TVExternalInput]>) -> Void) {
        subscribe(uri: "ssap://tv/getExternalInputList", payload: [:]) { response in
            completion(self.externalInputsResult(from: response))
        }
    }

    func switchHDMI(_ index: Int, inputID: String? = nil, completion: @escaping (LGResult<Void>) -> Void) {
        let safeIndex = min(max(index, 1), 4)
        let resolvedInputID = inputID.flatMap { $0.isEmpty ? nil : $0 } ?? "HDMI_\(safeIndex)"
        request(uri: "ssap://tv/switchInput", payload: ["inputId": resolvedInputID]) { response in
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

    func getForegroundAppID(completion: @escaping (LGResult<String>) -> Void) {
        request(uri: "ssap://com.webos.applicationManager/getForegroundAppInfo", payload: [:]) { response in
            completion(self.foregroundAppResult(from: response))
        }
    }

    func subscribeForegroundAppID(_ completion: @escaping (LGResult<String>) -> Void) {
        subscribe(uri: "ssap://com.webos.applicationManager/getForegroundAppInfo", payload: [:]) { response in
            completion(self.foregroundAppResult(from: response))
        }
    }

    func getCurrentHDMI(completion: @escaping (LGResult<Int?>) -> Void) {
        getForegroundAppID { result in
            switch result {
            case .success(let appID):
                completion(.success(Self.hdmiIndex(in: appID)))
            case .failure(let message):
                completion(.failure(message))
            }
        }
    }

    func getSoundOutput(completion: @escaping (LGResult<String>) -> Void) {
        request(uri: "ssap://com.webos.service.apiadapter/audio/getSoundOutput", payload: [:]) { response in
            completion(self.soundOutputResult(from: response))
        }
    }

    func subscribeSoundOutput(_ completion: @escaping (LGResult<String>) -> Void) {
        subscribe(uri: "ssap://com.webos.service.apiadapter/audio/getSoundOutput", payload: [:]) { response in
            completion(self.soundOutputResult(from: response))
        }
    }

    func changeSoundOutput(_ outputID: String, completion: @escaping (LGResult<Void>) -> Void) {
        request(
            uri: "ssap://com.webos.service.apiadapter/audio/changeSoundOutput",
            payload: ["output": outputID]
        ) { response in
            completion(self.resultFromResponse(response))
        }
    }

    private func request(uri: String, payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        sendRequest(type: "request", uri: uri, payload: payload, isSubscription: false, completion: completion)
    }

    private func subscribe(uri: String, payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        sendRequest(type: "subscribe", uri: uri, payload: payload, isSubscription: true, completion: completion)
    }

    private func sendRequest(
        type: String,
        uri: String,
        payload: [String: Any],
        isSubscription: Bool,
        completion: @escaping ([String: Any]) -> Void
    ) {
        guard isConnected else {
            logger.log("webos", "rejected while disconnected: \(type) \(uri)")
            completion(errorResponse(t(.notConnected)))
            return
        }

        let id = makeID()
        logger.log("webos", "send id=\(id) type=\(type) uri=\(uri)")
        if isSubscription {
            subscriptionIDs.insert(id)
        }
        pending[id] = { response in
            let dictionary = response as? [String: Any] ?? [:]
            let responseType = dictionary["type"] as? String ?? "unknown"
            self.logger.log("webos", "receive id=\(id) type=\(responseType) uri=\(uri)")
            completion(dictionary)
            return isSubscription ? self.resultFromResponse(dictionary).isFailure : true
        }
        requestCancellations[id] = { message in
            completion(self.errorResponse(message))
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.failPendingRequest(id: id, message: self?.t(.requestTimedOut) ?? "Request timed out")
        }
        requestTimeouts[id] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)

        send(dictionary: [
            "id": id,
            "type": type,
            "uri": uri,
            "payload": payload
        ]) { [weak self] in
            self?.failPendingRequest(id: id, message: self?.t(.sendFailed) ?? "Send failed")
        }
    }

    private func failPendingRequest(id: String, message: String) {
        guard pending.removeValue(forKey: id) != nil else { return }
        logger.log("webos", "request failed id=\(id): \(message)")
        subscriptionIDs.remove(id)
        requestTimeouts.removeValue(forKey: id)?.cancel()
        let cancellation = requestCancellations.removeValue(forKey: id)
        cancellation?(message)
    }

    private func sendVolumeStep(uri: String, remaining: Int, completion: @escaping (LGResult<Void>) -> Void) {
        guard remaining > 0 else {
            completion(.success(()))
            return
        }

        request(uri: uri, payload: [:]) { response in
            switch self.resultFromResponse(response) {
            case .success:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.sendVolumeStep(uri: uri, remaining: remaining - 1, completion: completion)
                }
            case .failure(let message):
                completion(.failure(message))
            }
        }
    }

    private func send(dictionary: [String: Any], onFailure: @escaping () -> Void = {}) {
        guard let task = webSocket,
              let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let text = String(data: data, encoding: .utf8) else {
            onFailure()
            return
        }

        task.send(.string(text)) { [weak self, weak task] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, let task, self.webSocket === task else { return }
                onFailure()
            }
        }
    }

    private func receiveLoop(for task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.webSocket === task else { return }
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
              let id = object["id"] as? String,
              let callback = pending[id] else {
            return
        }

        let shouldRemove = callback(object)
        if subscriptionIDs.contains(id) {
            requestTimeouts.removeValue(forKey: id)?.cancel()
            requestCancellations.removeValue(forKey: id)
            if shouldRemove {
                pending.removeValue(forKey: id)
                subscriptionIDs.remove(id)
            }
        } else if shouldRemove {
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

    private func volumeResult(from response: [String: Any]) -> LGResult<TVVolumeStatus> {
        if case .failure(let message) = resultFromResponse(response) {
            return .failure(message)
        }
        guard let payload = response["payload"] as? [String: Any],
              let status = WebOSResponseParser.volumeStatus(payload) else {
            return .failure(t(.volumeReadFailed))
        }
        return .success(status)
    }

    private func muteResult(from response: [String: Any]) -> LGResult<Bool> {
        if case .failure(let message) = resultFromResponse(response) {
            return .failure(message)
        }
        guard let payload = response["payload"] as? [String: Any],
              let muted = WebOSResponseParser.muteStatus(payload) else {
            return .failure(t(.volumeReadFailed))
        }
        return .success(muted)
    }

    private func externalInputsResult(from response: [String: Any]) -> LGResult<[TVExternalInput]> {
        if case .failure(let message) = resultFromResponse(response) {
            return .failure(message)
        }
        guard let payload = response["payload"] as? [String: Any] else {
            return .failure(t(.externalInputsReadFailed))
        }
        return .success(WebOSResponseParser.externalInputs(payload))
    }

    private func foregroundAppResult(from response: [String: Any]) -> LGResult<String> {
        if case .failure(let message) = resultFromResponse(response) {
            return .failure(message)
        }
        let payload = response["payload"] as? [String: Any]
        return .success(payload?["appId"] as? String ?? "")
    }

    private func soundOutputResult(from response: [String: Any]) -> LGResult<String> {
        if case .failure(let message) = resultFromResponse(response) {
            return .failure(message)
        }
        guard let payload = response["payload"] as? [String: Any],
              let output = WebOSResponseParser.soundOutput(payload),
              !output.isEmpty else {
            return .failure(t(.soundOutputReadFailed))
        }
        return .success(output)
    }

    private func resultFromResponse(_ response: [String: Any]) -> LGResult<Void> {
        if response["type"] as? String == "error" {
            let payload = response["payload"] as? [String: Any]
            return .failure(
                payload?["error"] as? String
                    ?? response["error"] as? String
                    ?? t(.commandRejected)
            )
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

    private func errorResponse(_ message: String) -> [String: Any] {
        ["type": "error", "payload": ["error": message]]
    }

    nonisolated static func hdmiIndex(in value: String) -> Int? {
        WebOSResponseParser.hdmiIndex(in: value)
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
        guard isConnected != connected else { return }
        isConnected = connected
        connectionStateChanged(connected)
    }

    private func handleTransportClosed() {
        logger.log("webos", "transport closed connected=\(isConnected)")
        if !currentConnectionHost.isEmpty,
           let trustFailure = trustValidator.consumeFailure(for: currentConnectionHost) {
            let key: L10n.Key = trustFailure == .certificateChanged ? .certificateChanged : .certificateSaveFailed
            if let connectionFailureHandler {
                connectionFailureHandler(t(key))
            } else {
                disconnect()
            }
            return
        }

        if isConnected {
            disconnect()
        } else {
            retryConnectionAttempt()
        }
    }

    private func retryConnectionAttempt() {
        guard !completionCalled, let fallback = connectionAttemptFallback else { return }
        connectionAttemptFallback = nil
        connectionFailureHandler = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        pending.removeAll()
        subscriptionIDs.removeAll()
        requestTimeouts.values.forEach { $0.cancel() }
        requestTimeouts.removeAll()
        requestCancellations.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        fallback()
    }

    private func finishConnection(_ result: LGResult<String>, completion: @escaping (LGResult<String>) -> Void) {
        guard !completionCalled else { return }
        completionCalled = true
        connectTimeout?.cancel()
        connectionAttemptFallback = nil
        connectionFailureHandler = nil
        pending.removeAll()
        subscriptionIDs.removeAll()
        requestTimeouts.values.forEach { $0.cancel() }
        requestTimeouts.removeAll()
        requestCancellations.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        currentConnectionHost = ""
        completion(result)
    }

    private func isPairingPromptResponse(type: String, payload: [String: Any]) -> Bool {
        if type == "response", payload["returnValue"] as? Bool == true {
            return true
        }
        return payload["pairingType"] as? String == "PROMPT"
    }

}

private extension LGResult {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

extension WebOSClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self, weak webSocketTask] in
            guard let self, let webSocketTask, self.webSocket === webSocketTask else { return }
            self.handleTransportClosed()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let result = trustValidator.evaluate(challenge)
        completionHandler(result.0, result.1)
    }
}
