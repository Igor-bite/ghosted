import CoreGraphics

public enum HandJoint: Hashable, Sendable {
    case wrist
    case indexMCP, indexPIP, indexTip
    case middleMCP, middlePIP, middleTip
    case ringMCP, ringPIP, ringTip
    case littleMCP, littlePIP, littleTip
}

/// Hand joints in normalized image coordinates. Missing joints = low confidence.
public struct HandPose: Sendable {
    public var points: [HandJoint: CGPoint]
    public init(points: [HandJoint: CGPoint]) { self.points = points }
}

/// Orientation-independent "V" (peace) sign heuristic:
/// a finger is extended when its tip is clearly farther from the wrist than its PIP joint
/// and roughly aligned with the MCP→PIP direction.
public enum VSignClassifier {
    public static func isVSign(_ pose: HandPose) -> Bool {
        guard let index = extended(pose, .indexMCP, .indexPIP, .indexTip),
              let middle = extended(pose, .middleMCP, .middlePIP, .middleTip),
              let ring = extended(pose, .ringMCP, .ringPIP, .ringTip),
              let little = extended(pose, .littleMCP, .littlePIP, .littleTip)
        else { return false }
        return index && middle && !ring && !little
    }

    /// nil when joints are missing.
    static func extended(_ pose: HandPose, _ mcp: HandJoint, _ pip: HandJoint, _ tip: HandJoint) -> Bool? {
        guard let w = pose.points[.wrist], let m = pose.points[mcp],
              let p = pose.points[pip], let t = pose.points[tip] else { return nil }
        let tipDist = dist(w, t)
        let pipDist = dist(w, p)
        guard pipDist > 0 else { return nil }
        // Direction alignment between MCP->PIP and PIP->TIP.
        let a = CGPoint(x: p.x - m.x, y: p.y - m.y)
        let b = CGPoint(x: t.x - p.x, y: t.y - p.y)
        let la = hypot(a.x, a.y), lb = hypot(b.x, b.y)
        guard la > 0, lb > 0 else { return false }
        let cos = (a.x * b.x + a.y * b.y) / (la * lb)
        return tipDist > pipDist * 1.15 && cos > 0.5
    }

    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
