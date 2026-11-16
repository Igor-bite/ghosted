import Foundation

/// Tracks whether frames stopped arriving.
public struct FrameWatchdog: Sendable {
    public var timeout: TimeInterval
    private var last: TimeInterval?

    public init(timeout: TimeInterval = 0.5) { self.timeout = timeout }

    public mutating func frameArrived(at time: TimeInterval) { last = time }

    public func isStale(now: TimeInterval) -> Bool {
        guard let last else { return true }
        return now - last > timeout
    }
}
