import AppKit

/// Decides whether a two-finger scroll gesture over the sidebar is a horizontal workspace swipe, and where the
/// page sits while the fingers are down. Vertical scrolling of the tab list and wheel mice (no gesture phases)
/// are never consumed.
struct WorkspaceSwipe {
    enum Direction: Equatable { case previous, next }
    enum Outcome: Equatable {
        case passThrough
        case consume
        /// The page offset to show: positive moves the page right and brings the previous workspace in from the left.
        case track(CGFloat)
        /// The fingers lifted. `nil` means the page springs back; `velocity` is the page's pt/s at release.
        case finish(Direction?, velocity: CGFloat)
    }
    struct Layout: Equatable {
        var width: CGFloat
        var hasPrevious: Bool
        var hasNext: Bool
    }

    static let lockDistance: CGFloat = 4
    static let horizontalDominance: CGFloat = 1.5
    /// Page travel per point of finger travel, as Arc responds to the same scroll events.
    static let travelScale: CGFloat = 0.47
    static let commitFraction: CGFloat = 1.0 / 3
    static let flickVelocity: CGFloat = 180
    static let flickMinimumOffset: CGFloat = 8
    static let rubberBandStiffness: CGFloat = 0.15
    static let velocityWindow: TimeInterval = 0.1

    var layout = Layout(width: 268, hasPrevious: true, hasNext: true)

    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var travelled = CGSize.zero
    private var samples: [(time: TimeInterval, offset: CGFloat)] = []
    private var swallowingMomentum = false

    /// `dx` is finger travel: positive when the fingers move right, whatever the natural-scrolling setting.
    mutating func feed(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase, time: TimeInterval) -> Outcome {
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
        let offset = displayedOffset()
        guard phase.contains(.ended) || phase.contains(.cancelled) else {
            samples.append((time, offset))
            return .track(offset)
        }
        let velocity = releaseVelocity(offset: offset, time: time)
        let direction: Direction = offset > 0 ? .previous : .next
        let hasNeighbour = direction == .previous ? layout.hasPrevious : layout.hasNext
        let flicked = abs(velocity) >= Self.flickVelocity && velocity * offset > 0 && abs(offset) >= Self.flickMinimumOffset
        let commit = phase.contains(.ended) && hasNeighbour && (abs(offset) >= Self.commitFraction * layout.width || flicked)
        reset()
        swallowingMomentum = true
        return .finish(commit ? direction : nil, velocity: velocity)
    }

    /// Finger travel scaled to the page, held to one page where a neighbour exists and resisted where none does.
    private func displayedOffset() -> CGFloat {
        let raw = travelled.width * Self.travelScale
        let hasNeighbour = raw > 0 ? layout.hasPrevious : layout.hasNext
        let magnitude = abs(raw)
        let shown = hasNeighbour ? min(magnitude, layout.width) : Self.resisted(magnitude, width: layout.width)
        return raw < 0 ? -shown : shown
    }

    static func resisted(_ distance: CGFloat, width: CGFloat) -> CGFloat {
        width * (1 - 1 / (distance * rubberBandStiffness / width + 1))
    }

    private func releaseVelocity(offset: CGFloat, time: TimeInterval) -> CGFloat {
        guard let first = samples.first(where: { time - $0.time <= Self.velocityWindow }) else { return 0 }
        return (offset - first.offset) / CGFloat(max(time - first.time, 0.016))
    }

    private mutating func reset() {
        axis = nil
        travelled = .zero
        samples = []
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
    /// Asked when a gesture begins, so the page width and the ends of the row are current.
    var layout: (() -> WorkspaceSwipe.Layout)?
    var onTrack: ((CGFloat) -> Void)?
    var onFinish: ((WorkspaceSwipe.Direction?, CGFloat) -> Void)?

    /// True when the event belongs to a horizontal workspace swipe and must not reach the scroll view.
    func handle(_ event: NSEvent) -> Bool {
        if event.phase.contains(.began) || event.phase.contains(.mayBegin), let layout { swipe.layout = layout() }
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let outcome = swipe.feed(dx: event.scrollingDeltaX * sign, dy: event.scrollingDeltaY * sign,
                                 phase: event.phase, momentum: event.momentumPhase, time: event.timestamp)
        switch outcome {
        case .passThrough: return false
        case .consume: return true
        case .track(let offset):
            onTrack?(offset)
            return true
        case .finish(let direction, let velocity):
            onFinish?(direction, velocity)
            return true
        }
    }
}

/// The workspace slide: pictures of the outgoing and neighbouring lists, clipped to the list area, move as one
/// strip while the neighbour's tint fades in behind the sidebar controls. The live list is hidden meanwhile.
@MainActor
final class SpaceSlide {
    struct Page {
        let image: CGImage
        let size: NSSize
        /// Distance from the top of the list area to the top of the picture.
        let top: CGFloat
    }

    let width: CGFloat
    private let backdrop = NSView()
    private let lists = NSView()
    private let clip = CALayer()
    private let slider = CALayer()
    private var tints: [WorkspaceSwipe.Direction: CALayer] = [:]
    private var neighbours: [WorkspaceSwipe.Direction: CALayer] = [:]
    private let scale: CGFloat
    private let appearance: NSAppearance
    private(set) var offset: CGFloat = 0

    static let releaseTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)

    /// `listFrame` is the list area in `root`'s coordinates. The backdrop goes beneath `stack`, the lists above it.
    init(root: NSView, stack: NSView, listFrame: NSRect) {
        width = listFrame.width
        scale = root.window?.backingScaleFactor ?? 2
        appearance = root.effectiveAppearance
        for view in [backdrop, lists] {
            view.frame = root.bounds
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
        }
        root.addSubview(backdrop, positioned: .below, relativeTo: stack)
        root.addSubview(lists, positioned: .above, relativeTo: stack)
        let area = lists.convert(listFrame, from: root)
        clip.frame = area
        clip.masksToBounds = true
        slider.frame = clip.bounds
        clip.addSublayer(slider)
        lists.layer?.addSublayer(clip)
    }

    func setCurrent(_ page: Page, fixedTop: Page?) {
        if let fixedTop { clip.addSublayer(layer(for: fixedTop, x: 0)) }
        slider.addSublayer(layer(for: page, x: 0))
    }

    func hasNeighbour(_ direction: WorkspaceSwipe.Direction) -> Bool { neighbours[direction] != nil }

    func addNeighbour(_ direction: WorkspaceSwipe.Direction, page: Page, accent: NSColor) {
        let layer = layer(for: page, x: direction == .previous ? -width : width)
        slider.addSublayer(layer)
        neighbours[direction] = layer
        let tint = CALayer()
        tint.frame = backdrop.bounds
        tint.contentsScale = scale
        tint.contents = Self.tintImage(accent, size: backdrop.bounds.size, appearance: appearance)
        tint.opacity = 0
        backdrop.layer?.addSublayer(tint)
        tints[direction] = tint
        setOffset(offset)
    }

    func setOffset(_ value: CGFloat) {
        offset = value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place(offset: value)
        CATransaction.commit()
    }

    func animate(to value: CGFloat, duration: CFTimeInterval, completion: @escaping () -> Void) {
        let from = offset
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        setOffset(value)
        ease(slider, "transform.translation.x", from: from, to: value, duration: duration)
        for (direction, tint) in tints {
            ease(tint, "opacity", from: tintOpacity(direction, offset: from), to: tintOpacity(direction, offset: value), duration: duration)
        }
        CATransaction.commit()
    }

    /// Reduce Motion: the neighbour fades in over the outgoing list instead of sliding.
    func crossfade(to direction: WorkspaceSwipe.Direction, duration: CFTimeInterval, completion: @escaping () -> Void) {
        guard let incoming = neighbours[direction], let tint = tints[direction] else { return completion() }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        CATransaction.setDisableActions(true)
        incoming.position.x = slider.bounds.midX
        incoming.opacity = 1
        tint.opacity = 1
        ease(incoming, "opacity", from: 0, to: 1, duration: duration)
        ease(tint, "opacity", from: tintOpacity(direction, offset: offset), to: 1, duration: duration)
        CATransaction.commit()
    }

    func remove() {
        backdrop.removeFromSuperview()
        lists.removeFromSuperview()
    }

    private func place(offset: CGFloat) {
        slider.transform = CATransform3DMakeTranslation(offset, 0, 0)
        for (direction, tint) in tints { tint.opacity = tintOpacity(direction, offset: offset) }
    }

    private func tintOpacity(_ direction: WorkspaceSwipe.Direction, offset: CGFloat) -> Float {
        Float(min(max((direction == .previous ? offset : -offset) / width, 0), 1))
    }

    /// Explicit rather than implicit: layers that have not been committed yet get no implicit animation, and a
    /// keyboard-driven slide starts in the same turn its layers are created.
    private func ease<Value: BinaryFloatingPoint>(_ layer: CALayer, _ keyPath: String, from: Value, to: Value, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = Double(from)
        animation.toValue = Double(to)
        animation.duration = duration
        animation.timingFunction = Self.releaseTiming
        layer.add(animation, forKey: keyPath)
    }

    private func layer(for page: Page, x: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contentsScale = scale
        layer.contents = page.image
        layer.frame = NSRect(x: x, y: clip.bounds.height - page.top - page.size.height,
                             width: page.size.width, height: page.size.height)
        return layer
    }

    private static func tintImage(_ accent: NSColor, size: NSSize, appearance: NSAppearance) -> CGImage? {
        let (top, bottom) = SidebarStyle.tint(accent, appearance: appearance)
        let image = NSImage(size: size, flipped: true) { rect in
            NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -90)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
