import Foundation

/// Debounces a noisy detector: fires once after `holdDuration` of continuous detection,
/// then not again until the detection is released and `cooldown` has passed since the last trigger.
public struct GestureGate: Sendable {
    public var holdDuration: TimeInterval
    public var cooldown: TimeInterval
    private var holdStart: TimeInterval?
    private var lastTrigger: TimeInterval = -.infinity
    private var firedThisHold = false

    public init(holdDuration: TimeInterval = 0.5, cooldown: TimeInterval = 2) {
        self.holdDuration = holdDuration
        self.cooldown = cooldown
    }

    /// Feed one detector sample. Returns true when the gesture should fire.
    public mutating func update(detected: Bool, now: TimeInterval) -> Bool {
        guard detected else {
            holdStart = nil
            firedThisHold = false
            return false
        }
        if holdStart == nil { holdStart = now }
        guard !firedThisHold, let start = holdStart else { return false }
        guard now - start >= holdDuration, now - lastTrigger >= cooldown else { return false }
        firedThisHold = true
        lastTrigger = now
        return true
    }

    /// Any trigger (hotkey, button, other gesture) starts the cooldown.
    public mutating func noteTrigger(now: TimeInterval) {
        lastTrigger = now
    }
}
