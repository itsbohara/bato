import AppKit

/// Decides whether a two-finger scroll gesture over the sidebar is a horizontal workspace swipe.
/// Vertical scrolling of the tab list and wheel mice (no gesture phases) are never consumed.
struct WorkspaceSwipe {
    enum Direction: Equatable { case previous, next }
    enum Outcome: Equatable {
        case passThrough
        case consume
        case switchWorkspace(Direction)
    }

    static let lockDistance: CGFloat = 4
    static let horizontalDominance: CGFloat = 1.5
    static let commitDistance: CGFloat = 60

    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var travelled = CGSize.zero
    private var swallowingMomentum = false

    /// `dx` is finger travel: positive when the fingers move right, whatever the natural-scrolling setting.
    mutating func feed(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) -> Outcome {
        if !momentum.isEmpty {
            defer { if momentum.contains(.ended) || momentum.contains(.cancelled) { swallowingMomentum = false } }
            return swallowingMomentum ? .consume : .passThrough
        }
        if phase.isEmpty { return .passThrough }
        if phase.contains(.began) || phase.contains(.mayBegin) { reset() }
        travelled.width += dx
        travelled.height += dy
        if axis == nil, abs(travelled.width) + abs(travelled.height) >= Self.lockDistance {
            axis = abs(travelled.width) > abs(travelled.height) * Self.horizontalDominance ? .horizontal : .vertical
        }
        guard axis == .horizontal else {
            if phase.contains(.ended) || phase.contains(.cancelled) { reset() }
            return .passThrough
        }
        guard phase.contains(.ended) || phase.contains(.cancelled) else { return .consume }
        let commit = phase.contains(.ended) && abs(travelled.width) >= Self.commitDistance
        let direction: Direction = travelled.width > 0 ? .previous : .next
        reset()
        swallowingMomentum = true
        return commit ? .switchWorkspace(direction) : .consume
    }

    private mutating func reset() {
        axis = nil
        travelled = .zero
        swallowingMomentum = false
    }
}

extension WorkspaceSwipe {
    /// The index a swipe lands on in a row of `count` pager dots, or nil at either end.
    static func target(from index: Int, direction: Direction, count: Int) -> Int? {
        let next = direction == .next ? index + 1 : index - 1
        return (0..<count).contains(next) ? next : nil
    }
}

@MainActor
final class WorkspaceSwipeRecognizer {
    private var swipe = WorkspaceSwipe()
    var onSwipe: ((WorkspaceSwipe.Direction) -> Void)?

    /// True when the event was a horizontal workspace swipe and must not reach the scroll view.
    func handle(_ event: NSEvent) -> Bool {
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let outcome = swipe.feed(dx: event.scrollingDeltaX * sign, dy: event.scrollingDeltaY * sign,
                                 phase: event.phase, momentum: event.momentumPhase)
        switch outcome {
        case .passThrough: return false
        case .consume: return true
        case .switchWorkspace(let direction):
            onSwipe?(direction)
            return true
        }
    }
}
