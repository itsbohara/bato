import AppKit
import XCTest
@testable import BatoBrowserUI

final class WorkspaceSwipeTests: XCTestCase {
    private func run(_ swipe: inout WorkspaceSwipe, _ steps: [(CGFloat, CGFloat, NSEvent.Phase)]) -> [WorkspaceSwipe.Outcome] {
        steps.map { swipe.feed(dx: $0.0, dy: $0.1, phase: $0.2, momentum: []) }
    }

    func testHorizontalSwipePastThresholdSwitchesOnEnd() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(20, 1, .began), (30, 2, .changed), (25, 0, .changed), (0, 0, .ended)])
        XCTAssertEqual(outcomes, [.consume, .consume, .consume, .switchWorkspace(.previous)])
    }

    func testLeftwardSwipeGoesNext() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(-40, 0, .began), (-40, 0, .changed), (0, 0, .ended)])
        XCTAssertEqual(outcomes.last, .switchWorkspace(.next))
    }

    func testShortSwipeDoesNotSwitch() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(10, 0, .began), (10, 0, .changed), (0, 0, .ended)])
        XCTAssertEqual(outcomes.last, .consume)
    }

    func testVerticalScrollPassesThrough() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(2, 30, .began), (5, 40, .changed), (3, 20, .changed), (0, 0, .ended)])
        XCTAssertEqual(outcomes, Array(repeating: .passThrough, count: 4))
    }

    func testDiagonalGestureStaysVertical() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(20, 20, .began), (60, 20, .changed), (0, 0, .ended)])
        XCTAssertEqual(outcomes, Array(repeating: .passThrough, count: 3))
    }

    func testWheelMouseWithoutPhasesPassesThrough() {
        var swipe = WorkspaceSwipe()
        XCTAssertEqual(swipe.feed(dx: 100, dy: 0, phase: [], momentum: []), .passThrough)
    }

    func testMomentumAfterSwipeIsSwallowedOnce() {
        var swipe = WorkspaceSwipe()
        _ = run(&swipe, [(40, 0, .began), (40, 0, .changed), (0, 0, .ended)])
        XCTAssertEqual(swipe.feed(dx: 9, dy: 0, phase: [], momentum: .changed), .consume)
        XCTAssertEqual(swipe.feed(dx: 3, dy: 0, phase: [], momentum: .ended), .consume)
        XCTAssertEqual(swipe.feed(dx: 3, dy: 0, phase: [], momentum: .changed), .passThrough)
    }

    func testNewGestureResetsAccumulation() {
        var swipe = WorkspaceSwipe()
        _ = run(&swipe, [(30, 0, .began), (0, 0, .cancelled)])
        let outcomes = run(&swipe, [(30, 0, .began), (0, 0, .ended)])
        XCTAssertEqual(outcomes.last, .consume)
    }

    func testTargetStopsAtEnds() {
        XCTAssertEqual(WorkspaceSwipe.target(from: 1, direction: .next, count: 3), 2)
        XCTAssertNil(WorkspaceSwipe.target(from: 2, direction: .next, count: 3))
        XCTAssertEqual(WorkspaceSwipe.target(from: 1, direction: .previous, count: 3), 0)
        XCTAssertNil(WorkspaceSwipe.target(from: 0, direction: .previous, count: 3))
    }
}
