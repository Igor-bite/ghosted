import XCTest
@testable import VanishCore

final class EffectStateMachineTests: XCTestCase {
    func testTriggerFromPresentStartsVanishing() {
        var sm = EffectStateMachine(duration: 2)
        XCTAssertEqual(sm.trigger(hasRoomPlate: true), .started)
        XCTAssertEqual(sm.phase, .vanishing(progress: 0))
        XCTAssertTrue(sm.isHidden == false)
    }

    func testTickCompletesVanishing() {
        var sm = EffectStateMachine(duration: 2)
        _ = sm.trigger(hasRoomPlate: true)
        sm.tick(dt: 1)
        XCTAssertEqual(sm.phase, .vanishing(progress: 0.5))
        sm.tick(dt: 1.5)
        XCTAssertEqual(sm.phase, .vanished)
        XCTAssertTrue(sm.isHidden)
    }

    func testTriggerMidVanishReverses() {
        var sm = EffectStateMachine(duration: 1)
        _ = sm.trigger(hasRoomPlate: true)
        sm.tick(dt: 0.3)
        XCTAssertEqual(sm.trigger(hasRoomPlate: true), .reversed)
        guard case .appearing(let p) = sm.phase else { return XCTFail("expected appearing") }
        XCTAssertEqual(p, 0.7, accuracy: 1e-9)
        sm.tick(dt: 0.3)
        XCTAssertEqual(sm.phase, .present)
    }

    func testTriggerFromVanishedStartsAppearing() {
        var sm = EffectStateMachine(duration: 1)
        sm.restore(vanished: true)
        XCTAssertEqual(sm.trigger(hasRoomPlate: true), .started)
        XCTAssertEqual(sm.phase, .appearing(progress: 0))
    }

    func testNoRoomPlateBlocksVanish() {
        var sm = EffectStateMachine(duration: 1)
        XCTAssertEqual(sm.trigger(hasRoomPlate: false), .needsRoomPlate)
        XCTAssertEqual(sm.phase, .present)
    }

    func testAppearingWithoutPlateStillAllowed() {
        var sm = EffectStateMachine(duration: 1)
        sm.restore(vanished: true)
        XCTAssertEqual(sm.trigger(hasRoomPlate: false), .started)
    }

    func testRestoreVanishedHasNoAnimation() {
        var sm = EffectStateMachine(duration: 1)
        sm.restore(vanished: true)
        XCTAssertEqual(sm.phase, .vanished)
        sm.restore(vanished: false)
        XCTAssertEqual(sm.phase, .present)
    }

    func testPersistedHiddenTarget() {
        var sm = EffectStateMachine(duration: 1)
        _ = sm.trigger(hasRoomPlate: true)
        XCTAssertTrue(sm.targetHidden)
        sm.tick(dt: 0.2)
        _ = sm.trigger(hasRoomPlate: true)
        XCTAssertFalse(sm.targetHidden)
    }
}
