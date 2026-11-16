import Foundation

/// Visual phase of the vanish effect. Progress is 0...1 within an animation.
public enum EffectPhase: Equatable, Sendable {
    case present
    case vanishing(progress: Double)
    case vanished
    case appearing(progress: Double)
}

public enum TriggerResult: Equatable, Sendable {
    case started
    case reversed
    case needsRoomPlate
}

/// Pure state machine for vanish/appear. Time is advanced explicitly via `tick`.
public struct EffectStateMachine: Sendable {
    public private(set) var phase: EffectPhase = .present
    public var duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = max(0.01, duration)
    }

    /// True when the person should not be visible at all (fully vanished).
    public var isHidden: Bool { phase == .vanished }

    /// The state the machine is heading to (persisted so a restart restores it).
    public var targetHidden: Bool {
        switch phase {
        case .present, .appearing: return false
        case .vanished, .vanishing: return true
        }
    }

    public var isAnimating: Bool {
        switch phase {
        case .vanishing, .appearing: return true
        default: return false
        }
    }

    public mutating func trigger(hasRoomPlate: Bool) -> TriggerResult {
        switch phase {
        case .present:
            guard hasRoomPlate else { return .needsRoomPlate }
            phase = .vanishing(progress: 0)
            return .started
        case .vanished:
            phase = .appearing(progress: 0)
            return .started
        case .vanishing(let p):
            phase = .appearing(progress: 1 - p)
            return .reversed
        case .appearing(let p):
            guard hasRoomPlate else { return .needsRoomPlate }
            phase = .vanishing(progress: 1 - p)
            return .reversed
        }
    }

    public mutating func tick(dt: TimeInterval) {
        let step = dt / duration
        switch phase {
        case .vanishing(let p):
            let n = p + step
            phase = n >= 1 ? .vanished : .vanishing(progress: n)
        case .appearing(let p):
            let n = p + step
            phase = n >= 1 ? .present : .appearing(progress: n)
        default:
            break
        }
    }

    /// Jump to a resting state without animation (used on app restart).
    public mutating func restore(vanished: Bool) {
        phase = vanished ? .vanished : .present
    }
}
