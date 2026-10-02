import Foundation

/// A queued volume request. Slider input is an absolute target; keyboard input is a count of
/// native volumeUp/volumeDown steps so rapid key presses never turn into an absolute setVolume.
enum VolumeWork: Equatable {
    case absolute(Int)
    case steps(Int)

    static let maximumStepBatch = 5

    /// Adds keyboard steps to the queued work. A queued slider target absorbs the steps so the
    /// latest explicit target still wins.
    static func adding(steps delta: Int, to pending: VolumeWork?) -> VolumeWork? {
        switch pending {
        case .absolute(let target):
            return .absolute(min(max(target + delta, 0), 100))
        case .steps(let queued):
            let total = min(max(queued + delta, -100), 100)
            return total == 0 ? nil : .steps(total)
        case nil:
            return delta == 0 ? nil : .steps(min(max(delta, -100), 100))
        }
    }

    /// Splits queued work into the batch to send now and the remainder that stays queued.
    static func takeBatch(from work: VolumeWork) -> (batch: VolumeWork, remainder: VolumeWork?) {
        switch work {
        case .absolute:
            return (work, nil)
        case .steps(let count):
            let direction = count > 0 ? 1 : -1
            let batch = direction * min(abs(count), maximumStepBatch)
            let remainder = count - batch
            return (.steps(batch), remainder == 0 ? nil : .steps(remainder))
        }
    }
}
