import Foundation

@MainActor
protocol TVVolumeControlling: AnyObject {
    func getVolume(completion: @escaping (LGResult<TVVolumeStatus>) -> Void)
    func setVolume(_ volume: Int, completion: @escaping (LGResult<Void>) -> Void)
    func changeVolume(delta: Int, completion: @escaping (LGResult<Void>) -> Void)
}

@MainActor
final class VolumeCommandExecutor {
    typealias Delay = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    private enum Strategy {
        case absolute
        case stepped
    }

    private let controller: TVVolumeControlling
    private let logger: DiagnosticsLogger
    private let delay: Delay
    private let verificationFailure: () -> String

    init(
        controller: TVVolumeControlling,
        logger: DiagnosticsLogger = .shared,
        delay: @escaping Delay = { seconds, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
        },
        verificationFailure: @escaping () -> String
    ) {
        self.controller = controller
        self.logger = logger
        self.delay = delay
        self.verificationFailure = verificationFailure
    }

    func execute(target: Int, current: Int, completion: @escaping (LGResult<TVVolumeStatus>) -> Void) {
        let target = min(max(target, 0), 100)
        let current = min(max(current, 0), 100)
        guard target != current else {
            verify(target: target, completion: completion)
            return
        }

        if abs(target - current) == 1 {
            executeNativeStep(target: target, current: current, completion: completion)
            return
        }

        let primary: Strategy = .absolute
        logger.log("volume", "command target=\(target) current=\(current) primary=\(primary)")
        send(primary, target: target, current: current) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.retryAlternate(after: current, target: target, primary: primary, completion: completion)
            case .success:
                self.delay(0.35) {
                    self.verify(target: target) { verification in
                        switch verification {
                        case .success:
                            completion(verification)
                        case .failure:
                            self.readCurrentAndRetry(
                                target: target,
                                primary: primary,
                                fallbackCurrent: current,
                                completion: completion
                            )
                        }
                    }
                }
            }
        }
    }

    private func executeNativeStep(
        target: Int,
        current: Int,
        completion: @escaping (LGResult<TVVolumeStatus>) -> Void
    ) {
        let direction = target > current ? 1 : -1
        logger.log("volume", "native step direction=\(direction) current=\(current)")
        controller.changeVolume(delta: direction) { [weak self] result in
            guard let self else { return }
            guard case .success = result else {
                completion(.failure(self.verificationFailure()))
                return
            }
            self.delay(0.35) {
                self.controller.getVolume { result in
                    switch result {
                    case .success(let status)
                        where (direction > 0 && status.volume > current)
                            || (direction < 0 && status.volume < current):
                        self.logger.log("volume", "native step verified actual=\(status.volume)")
                        completion(.success(status))
                    case .success(let status):
                        self.logger.log(
                            "volume",
                            "native step unchanged direction=\(direction) current=\(current) actual=\(status.volume)"
                        )
                        completion(.failure(self.verificationFailure()))
                    case .failure(let message):
                        self.logger.log("volume", "native step read failed: \(message)")
                        completion(.failure(message))
                    }
                }
            }
        }
    }

    private func readCurrentAndRetry(
        target: Int,
        primary: Strategy,
        fallbackCurrent: Int,
        completion: @escaping (LGResult<TVVolumeStatus>) -> Void
    ) {
        controller.getVolume { [weak self] result in
            guard let self else { return }
            let current = result.value?.volume ?? fallbackCurrent
            self.retryAlternate(after: current, target: target, primary: primary, completion: completion)
        }
    }

    private func retryAlternate(
        after current: Int,
        target: Int,
        primary: Strategy,
        completion: @escaping (LGResult<TVVolumeStatus>) -> Void
    ) {
        let alternate: Strategy = primary == .absolute ? .stepped : .absolute
        logger.log("volume", "retry target=\(target) observed=\(current) strategy=\(alternate)")
        send(alternate, target: target, current: current) { [weak self] result in
            guard let self else { return }
            guard case .success = result else {
                completion(.failure(self.verificationFailure()))
                return
            }
            self.delay(0.45) {
                self.verify(target: target, completion: completion)
            }
        }
    }

    private func send(
        _ strategy: Strategy,
        target: Int,
        current: Int,
        completion: @escaping (LGResult<Void>) -> Void
    ) {
        switch strategy {
        case .absolute:
            controller.setVolume(target, completion: completion)
        case .stepped:
            controller.changeVolume(delta: target - current, completion: completion)
        }
    }

    private func verify(target: Int, completion: @escaping (LGResult<TVVolumeStatus>) -> Void) {
        controller.getVolume { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let status) where status.volume == target:
                self.logger.log("volume", "verified target=\(target)")
                completion(.success(status))
            case .success(let status):
                self.logger.log("volume", "verification mismatch target=\(target) actual=\(status.volume)")
                completion(.failure(self.verificationFailure()))
            case .failure(let message):
                self.logger.log("volume", "verification read failed: \(message)")
                completion(.failure(message))
            }
        }
    }
}

extension WebOSClient: TVVolumeControlling {}

private extension LGResult {
    var value: Value? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}
