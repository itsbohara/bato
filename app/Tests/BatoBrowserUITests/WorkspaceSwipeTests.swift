import AppKit
import XCTest
@testable import BatoBrowserUI

final class WorkspaceSwipeTests: XCTestCase {
    private typealias Step = (dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, time: TimeInterval)

    private func run(_ swipe: inout WorkspaceSwipe, _ steps: [Step]) -> [WorkspaceSwipe.Outcome] {
        steps.map { swipe.feed(dx: $0.dx, dy: $0.dy, phase: $0.phase, momentum: [], time: $0.time) }
    }

    /// A drag of `total` finger points over `duration`, then a lift after `hold`.
    private func drag(_ swipe: inout WorkspaceSwipe, total: CGFloat, duration: TimeInterval, hold: TimeInterval = 0) -> WorkspaceSwipe.Outcome {
        let count = 10
        for index in 0..<count {
            _ = swipe.feed(dx: total / CGFloat(count), dy: 0, phase: index == 0 ? .began : .changed, momentum: [],
                           time: duration * Double(index + 1) / Double(count))
        }
        return swipe.feed(dx: 0, dy: 0, phase: .ended, momentum: [], time: duration + hold)
    }

    private func offset(_ outcome: WorkspaceSwipe.Outcome) -> CGFloat? {
        if case .track(let value) = outcome { return value }
        return nil
    }

    func testTrackingFollowsFingersScaledToThePage() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(20, 1, .began, 0), (30, 2, .changed, 0.016), (50, 0, .changed, 0.032)])
        XCTAssertEqual(offset(outcomes[2]) ?? 0, 100 * WorkspaceSwipe.travelScale, accuracy: 0.001)
    }

    func testRightwardSwipePastThirdOfWidthCommitsPrevious() {
        var swipe = WorkspaceSwipe()
        let outcome = drag(&swipe, total: 220, duration: 0.8, hold: 0.2)
        guard case .finish(let direction, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(direction, .previous)
    }

    func testLeftwardSwipeGoesNext() {
        var swipe = WorkspaceSwipe()
        let outcome = drag(&swipe, total: -220, duration: 0.8, hold: 0.2)
        guard case .finish(let direction, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(direction, .next)
    }

    func testSlowShortDragReleasesToCancel() {
        var swipe = WorkspaceSwipe()
        let outcome = drag(&swipe, total: 120, duration: 0.6, hold: 0.2)
        guard case .finish(let direction, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(direction)
    }

    func testFastFlickCommitsBelowDistanceThreshold() {
        var swipe = WorkspaceSwipe()
        let outcome = drag(&swipe, total: 100, duration: 0.15)
        guard case .finish(let direction, let velocity) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(direction, .previous)
        XCTAssertGreaterThan(velocity, WorkspaceSwipe.flickVelocity)
    }

    func testPausingBeforeLiftingDropsTheFlick() {
        var swipe = WorkspaceSwipe()
        let outcome = drag(&swipe, total: 100, duration: 0.15, hold: 0.3)
        guard case .finish(let direction, let velocity) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(direction)
        XCTAssertEqual(velocity, 0)
    }

    func testTinyFastTwitchDoesNotCommit() {
        var swipe = WorkspaceSwipe()
        let outcome = drag(&swipe, total: 10, duration: 0.02)
        guard case .finish(let direction, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(direction)
    }

    func testCancelledGestureNeverCommits() {
        var swipe = WorkspaceSwipe()
        _ = run(&swipe, [(300, 0, .began, 0), (300, 0, .changed, 0.1)])
        let outcome = swipe.feed(dx: 0, dy: 0, phase: .cancelled, momentum: [], time: 0.12)
        guard case .finish(let direction, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(direction)
    }

    func testOffsetStopsAtOnePage() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(900, 0, .began, 0), (900, 0, .changed, 0.1)])
        XCTAssertEqual(offset(outcomes[1]), swipe.layout.width)
    }

    func testRubberBandResistsWhereNoNeighbourExists() {
        var swipe = WorkspaceSwipe()
        swipe.layout = .init(width: 268, hasPrevious: false, hasNext: true)
        let outcomes = run(&swipe, [(250, 0, .began, 0), (250, 0, .changed, 0.1)])
        let shown = offset(outcomes[1]) ?? 0
        XCTAssertGreaterThan(shown, 0)
        XCTAssertLessThan(shown, 60)
        XCTAssertLessThan(shown, 500 * WorkspaceSwipe.travelScale)
    }

    func testRubberBandReleaseNeverCommits() {
        var swipe = WorkspaceSwipe()
        swipe.layout = .init(width: 268, hasPrevious: false, hasNext: false)
        let outcome = drag(&swipe, total: 900, duration: 0.1)
        guard case .finish(let direction, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(direction)
    }

    func testResistedDistanceGrowsSlowlyAndStaysBelowPage() {
        let width: CGFloat = 268
        XCTAssertLessThan(WorkspaceSwipe.resisted(10, width: width), 10)
        XCTAssertLessThan(WorkspaceSwipe.resisted(235, width: width), 40)
        XCTAssertLessThan(WorkspaceSwipe.resisted(100_000, width: width), width)
        XCTAssertGreaterThan(WorkspaceSwipe.resisted(200, width: width), WorkspaceSwipe.resisted(100, width: width))
    }

    func testVerticalScrollPassesThrough() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(2, 30, .began, 0), (5, 40, .changed, 0.01), (3, 20, .changed, 0.02), (0, 0, .ended, 0.03)])
        XCTAssertEqual(outcomes, Array(repeating: .passThrough, count: 4))
    }

    func testDiagonalGestureStaysVertical() {
        var swipe = WorkspaceSwipe()
        let outcomes = run(&swipe, [(20, 20, .began, 0), (60, 20, .changed, 0.01), (0, 0, .ended, 0.02)])
        XCTAssertEqual(outcomes, Array(repeating: .passThrough, count: 3))
    }

    func testWheelMouseWithoutPhasesPassesThrough() {
        var swipe = WorkspaceSwipe()
        XCTAssertEqual(swipe.feed(dx: 100, dy: 0, phase: [], momentum: [], time: 0), .passThrough)
    }

    func testMomentumAfterSwipeIsSwallowedOnce() {
        var swipe = WorkspaceSwipe()
        _ = drag(&swipe, total: 220, duration: 0.5)
        XCTAssertEqual(swipe.feed(dx: 9, dy: 0, phase: [], momentum: .changed, time: 0.6), .consume)
        XCTAssertEqual(swipe.feed(dx: 3, dy: 0, phase: [], momentum: .ended, time: 0.7), .consume)
        XCTAssertEqual(swipe.feed(dx: 3, dy: 0, phase: [], momentum: .changed, time: 0.8), .passThrough)
    }

    func testNewGestureResetsAccumulation() {
        var swipe = WorkspaceSwipe()
        _ = run(&swipe, [(300, 0, .began, 0), (0, 0, .cancelled, 0.1)])
        let outcomes = run(&swipe, [(30, 0, .began, 1), (0, 0, .ended, 1.5)])
        XCTAssertEqual(offset(outcomes[0]) ?? 0, 30 * WorkspaceSwipe.travelScale, accuracy: 0.001)
    }

    func testTargetStopsAtEnds() {
        XCTAssertEqual(WorkspaceSwipe.target(from: 1, direction: .next, count: 3), 2)
        XCTAssertNil(WorkspaceSwipe.target(from: 2, direction: .next, count: 3))
        XCTAssertEqual(WorkspaceSwipe.target(from: 1, direction: .previous, count: 3), 0)
        XCTAssertNil(WorkspaceSwipe.target(from: 0, direction: .previous, count: 3))
    }
}
