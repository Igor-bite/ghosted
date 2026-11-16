import XCTest
import CoreGraphics
@testable import VanishCore

final class GeometryTests: XCTestCase {
    func testAspectFillCropsTallSource() {
        let r = aspectFillRect(source: CGSize(width: 1920, height: 1440), target: CGSize(width: 1280, height: 720))
        XCTAssertEqual(r, CGRect(x: 0, y: 180, width: 1920, height: 1080))
    }

    func testAspectFillCropsWideSource() {
        let r = aspectFillRect(source: CGSize(width: 2560, height: 1080), target: CGSize(width: 1280, height: 720))
        XCTAssertEqual(r.height, 1080)
        XCTAssertEqual(r.width, 1920)
        XCTAssertEqual(r.minX, 320)
    }

    func testAspectFillIdentity() {
        let r = aspectFillRect(source: CGSize(width: 1280, height: 720), target: CGSize(width: 1280, height: 720))
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 1280, height: 720))
    }
}

final class VSignTests: XCTestCase {
    /// Hand pointing up in normalized image coords (y up). Wrist at bottom.
    private func pose(indexUp: Bool, middleUp: Bool, ringUp: Bool, littleUp: Bool) -> HandPose {
        var p: [HandJoint: CGPoint] = [.wrist: CGPoint(x: 0.5, y: 0.2)]
        func finger(_ mcp: HandJoint, _ pip: HandJoint, _ tip: HandJoint, x: CGFloat, up: Bool) {
            p[mcp] = CGPoint(x: x, y: 0.35)
            p[pip] = CGPoint(x: x, y: up ? 0.45 : 0.38)
            p[tip] = CGPoint(x: x, y: up ? 0.60 : 0.30)
        }
        finger(.indexMCP, .indexPIP, .indexTip, x: 0.44, up: indexUp)
        finger(.middleMCP, .middlePIP, .middleTip, x: 0.50, up: middleUp)
        finger(.ringMCP, .ringPIP, .ringTip, x: 0.55, up: ringUp)
        finger(.littleMCP, .littlePIP, .littleTip, x: 0.60, up: littleUp)
        return HandPose(points: p)
    }

    func testVSignDetected() {
        XCTAssertTrue(VSignClassifier.isVSign(pose(indexUp: true, middleUp: true, ringUp: false, littleUp: false)))
    }

    func testOpenPalmRejected() {
        XCTAssertFalse(VSignClassifier.isVSign(pose(indexUp: true, middleUp: true, ringUp: true, littleUp: true)))
    }

    func testFistRejected() {
        XCTAssertFalse(VSignClassifier.isVSign(pose(indexUp: false, middleUp: false, ringUp: false, littleUp: false)))
    }

    func testPointingRejected() {
        XCTAssertFalse(VSignClassifier.isVSign(pose(indexUp: true, middleUp: false, ringUp: false, littleUp: false)))
    }

    func testMissingJointsRejected() {
        XCTAssertFalse(VSignClassifier.isVSign(HandPose(points: [.wrist: .zero])))
    }
}

final class GestureGateTests: XCTestCase {
    func testRequiresHold() {
        var g = GestureGate(holdDuration: 0.5, cooldown: 2)
        XCTAssertFalse(g.update(detected: true, now: 0))
        XCTAssertFalse(g.update(detected: true, now: 0.3))
        XCTAssertTrue(g.update(detected: true, now: 0.5))
    }

    func testInterruptedHoldResets() {
        var g = GestureGate(holdDuration: 0.5, cooldown: 2)
        _ = g.update(detected: true, now: 0)
        _ = g.update(detected: false, now: 0.3)
        XCTAssertFalse(g.update(detected: true, now: 0.6))
        XCTAssertTrue(g.update(detected: true, now: 1.1))
    }

    func testCooldownAfterFire() {
        var g = GestureGate(holdDuration: 0.5, cooldown: 2)
        _ = g.update(detected: true, now: 0)
        XCTAssertTrue(g.update(detected: true, now: 0.5))
        // still holding: must not refire
        XCTAssertFalse(g.update(detected: true, now: 1.5))
        _ = g.update(detected: false, now: 1.6)
        _ = g.update(detected: true, now: 1.7)
        XCTAssertFalse(g.update(detected: true, now: 2.3)) // within cooldown (fired at 0.5)
        _ = g.update(detected: false, now: 2.6)
        _ = g.update(detected: true, now: 2.6)
        XCTAssertTrue(g.update(detected: true, now: 3.1))
    }

    func testExternalTriggerStartsCooldown() {
        var g = GestureGate(holdDuration: 0.5, cooldown: 2)
        g.noteTrigger(now: 0)
        _ = g.update(detected: true, now: 0.1)
        XCTAssertFalse(g.update(detected: true, now: 0.7))
    }

    func testInstantEventGate() {
        var g = GestureGate(holdDuration: 0, cooldown: 2)
        XCTAssertTrue(g.update(detected: true, now: 0))
        XCTAssertFalse(g.update(detected: true, now: 1))
    }
}

final class RoomPlateStatsTests: XCTestCase {
    func testMedian() {
        XCTAssertEqual(RoomPlateStats.median([[1, 10], [9, 20], [5, 30]]), [5, 20])
    }

    func testMedianEvenCountUsesLowerMiddle() {
        XCTAssertEqual(RoomPlateStats.median([[1], [2], [3], [4]]), [2])
    }

    func testCoverage() {
        XCTAssertEqual(RoomPlateStats.coverage(mask: [0, 255, 200, 10], threshold: 128), 0.5)
        XCTAssertEqual(RoomPlateStats.coverage(mask: [], threshold: 128), 0)
    }

    func testPersonThreshold() {
        XCTAssertTrue(RoomPlateStats.containsPerson(coverage: 0.011))
        XCTAssertFalse(RoomPlateStats.containsPerson(coverage: 0.009))
    }
}

final class FrameWatchdogTests: XCTestCase {
    func testStaleWithoutFrames() {
        let w = FrameWatchdog(timeout: 0.5)
        XCTAssertTrue(w.isStale(now: 100))
    }

    func testFreshAfterFrame() {
        var w = FrameWatchdog(timeout: 0.5)
        w.frameArrived(at: 10)
        XCTAssertFalse(w.isStale(now: 10.4))
        XCTAssertTrue(w.isStale(now: 10.6))
    }
}

final class ClientInfoTests: XCTestCase {
    func testRoundTrip() {
        let info = ClientInfo(count: 2, signingID: "us.zoom.xos")
        XCTAssertEqual(ClientInfo(encoded: info.encoded), info)
    }

    func testNilSigningID() {
        let info = ClientInfo(count: 0, signingID: nil)
        XCTAssertEqual(info.encoded, "0|")
        XCTAssertEqual(ClientInfo(encoded: "0|"), info)
    }

    func testFriendlyName() {
        XCTAssertEqual(ClientInfo.friendlyName(for: "us.zoom.xos"), "Zoom")
        XCTAssertEqual(ClientInfo.friendlyName(for: "com.google.Chrome"), "Google Chrome")
        XCTAssertEqual(ClientInfo.friendlyName(for: "org.example.Unknown"), "org.example.Unknown")
    }
}
