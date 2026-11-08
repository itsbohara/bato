import AppKit
import BatoCore

extension NSPasteboard.PasteboardType {
    static let batoEntry = NSPasteboard.PasteboardType("com.itsbohara.bato.sidebar-entry")
}

/// A sidebar view a drag can land on or next to, in the sidebar entries' coordinate space.
struct SidebarDropSlot: Equatable {
    enum Kind: Equatable {
        case tile(index: Int)
        case row(section: BrowserState.SidebarSection, index: Int)
        case folder(id: UUID, pinCount: Int)
        case newTabRow
        case emptyFavorites
    }
    var kind: Kind
    var frame: NSRect
}

struct SidebarDropTarget: Equatable {
    enum Indicator: Equatable {
        case line(NSRect)
        case highlight(NSRect)
    }
    var section: BrowserState.SidebarSection
    var index: Int
    var indicator: Indicator
}

/// Pure hit-testing from a pointer to a placement, so every move kind is covered without AppKit drags.
enum SidebarDropMap {
    static let lineThickness: CGFloat = 2
    static let tileLineThickness: CGFloat = 3
    private static let rowGap: CGFloat = 2.5

    static let shiftAmount: CGFloat = 10

    /// Rows below an insertion line move down to open a gap; the line is recentred in that gap.
    static func shiftPlan(line: NSRect, slots: [SidebarDropSlot], amount: CGFloat = shiftAmount) -> (shifted: [Int], line: NSRect) {
        guard line.width > line.height else { return ([], line) }
        let shifted = slots.indices.filter { index in
            switch slots[index].kind {
            case .row, .folder, .newTabRow: return slots[index].frame.midY > line.midY
            case .tile, .emptyFavorites: return false
            }
        }
        guard !shifted.isEmpty else { return ([], line) }
        return (shifted, line.offsetBy(dx: 0, dy: amount / 2))
    }

    static func resolve(point: NSPoint, slots: [SidebarDropSlot], unfiledPinCount: Int) -> SidebarDropTarget? {
        for slot in slots {
            if case .emptyFavorites = slot.kind, slot.frame.contains(point) {
                return SidebarDropTarget(section: .favorites, index: 0, indicator: .highlight(slot.frame))
            }
        }
        for slot in slots {
            if case .folder(let id, let count) = slot.kind, slot.frame.contains(point) {
                return SidebarDropTarget(section: .pinned(folder: id), index: count, indicator: .highlight(slot.frame))
            }
        }
        let tiles = slots.filter { if case .tile = $0.kind { return true } else { return false } }
        if let lastTile = tiles.last, point.y <= lastTile.frame.maxY + 4 {
            return resolveTile(point: point, tiles: tiles)
        }
        let candidates = slots.filter {
            switch $0.kind {
            case .row, .newTabRow: return true
            case .tile, .folder, .emptyFavorites: return false
            }
        }
        guard let nearest = candidates.min(by: { distance(point.y, $0.frame) < distance(point.y, $1.frame) }) else { return nil }
        let frame = nearest.frame
        switch nearest.kind {
        case .row(let section, let index):
            let after = point.y >= frame.midY
            return SidebarDropTarget(section: section, index: after ? index + 1 : index,
                                     indicator: .line(horizontalLine(at: after ? frame.maxY : frame.minY, in: frame)))
        case .newTabRow:
            if point.y < frame.midY {
                return SidebarDropTarget(section: .pinned(folder: nil), index: unfiledPinCount,
                                         indicator: .line(horizontalLine(at: frame.minY, in: frame)))
            }
            return SidebarDropTarget(section: .tabs, index: 0, indicator: .line(horizontalLine(at: frame.maxY, in: frame)))
        case .tile, .folder, .emptyFavorites:
            return nil
        }
    }

    private static func resolveTile(point: NSPoint, tiles: [SidebarDropSlot]) -> SidebarDropTarget? {
        guard let nearest = tiles.min(by: { distance(point.y, $0.frame) < distance(point.y, $1.frame) }) else { return nil }
        let row = tiles.filter { $0.frame.minY == nearest.frame.minY }
        guard let last = row.last else { return nil }
        for slot in row {
            guard case .tile(let index) = slot.kind, point.x < slot.frame.midX else { continue }
            return SidebarDropTarget(section: .favorites, index: index, indicator: .line(verticalLine(at: slot.frame.minX - 2, in: slot.frame)))
        }
        guard case .tile(let index) = last.kind else { return nil }
        return SidebarDropTarget(section: .favorites, index: index + 1, indicator: .line(verticalLine(at: last.frame.maxX + 2, in: last.frame)))
    }

    private static func distance(_ y: CGFloat, _ frame: NSRect) -> CGFloat {
        y < frame.minY ? frame.minY - y : (y > frame.maxY ? y - frame.maxY : 0)
    }

    private static func horizontalLine(at edge: CGFloat, in frame: NSRect) -> NSRect {
        let centre = edge + (edge == frame.minY ? -rowGap : rowGap)
        return NSRect(x: frame.minX + 6, y: centre - lineThickness / 2, width: frame.width - 12, height: lineThickness)
    }

    /// Kept clear of the sidebar's leading edge, where the first slot's line would otherwise be clipped.
    private static func verticalLine(at x: CGFloat, in frame: NSRect) -> NSRect {
        NSRect(x: max(x - tileLineThickness / 2, 3), y: frame.minY + 2, width: tileLineThickness, height: frame.height - 4)
    }
}

/// The stack holding every sidebar row. It is also the one drag destination: rows register slots, this view
/// resolves the pointer against them and draws the insertion line or folder highlight.
@MainActor
final class SidebarEntries: NSStackView {
    // NSClipView uses the document's coordinate direction when its height is
    // shorter than the viewport. Top-origin content stays below address entry
    // instead of being bottom-aligned above the workspace footer.
    override var isFlipped: Bool { true }

    var slotViews: (() -> [(view: NSView, kind: SidebarDropSlot.Kind)])?
    var resolveDrop: ((UUID, NSPoint) -> SidebarDropTarget?)?
    var performDrop: ((UUID, SidebarDropTarget) -> Bool)?
    var accent: NSColor = .controlAccentColor
    private let indicator = NSView()
    private var pending: SidebarDropTarget?
    private var shiftedViews: [NSView] = []
    private var favoritesZone: FavoritesDropZone?
    private var wantsFavoritesZone = false

    /// The empty-Favorites drop area as a slot, so hit testing treats it like any other sidebar view.
    var favoritesZoneSlot: SidebarDropSlot? {
        guard let zone = favoritesZone, zone.window != nil else { return nil }
        return SidebarDropSlot(kind: .emptyFavorites, frame: convert(zone.bounds, from: zone))
    }

    /// With no Essentials there is no tile to drop next to, so a dashed area is offered at the top.
    func setFavoritesZone(visible: Bool) {
        wantsFavoritesZone = visible
        if visible {
            guard favoritesZone?.superview !== self else { return }
            let zone = favoritesZone ?? FavoritesDropZone()
            favoritesZone = zone
            zone.alphaValue = 0
            insertArrangedSubview(zone, at: 0)
            zone.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; zone.animator().alphaValue = 1 }
        } else if let zone = favoritesZone {
            removeArrangedSubview(zone)
            zone.removeFromSuperview()
            favoritesZone = nil
        }
    }

    /// `render()` empties the stack, which would drop the zone out from under a drag still in flight.
    func restoreFavoritesZone() {
        guard wantsFavoritesZone else { return }
        favoritesZone = nil
        setFavoritesZone(visible: true)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.batoEntry])
        indicator.wantsLayer = true
        indicator.isHidden = true
        indicator.setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    private func entryID(_ sender: any NSDraggingInfo) -> UUID? {
        sender.draggingPasteboard.string(forType: .batoEntry).flatMap(UUID.init(uuidString:))
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let id = entryID(sender),
              let target = resolveDrop?(id, convert(sender.draggingLocation, from: nil)) else {
            pending = nil
            indicator.isHidden = true
            return []
        }
        pending = target
        show(target.indicator)
        favoritesZone?.isTargeted = target.section == .favorites
        return .move
    }

    private func applyShift(for shape: SidebarDropTarget.Indicator) -> SidebarDropTarget.Indicator {
        guard case .line(let line) = shape, let views = slotViews?() else {
            setShifted([])
            return shape
        }
        let slots = views.map { SidebarDropSlot(kind: $0.kind, frame: convert($0.view.bounds, from: $0.view)) }
        let plan = SidebarDropMap.shiftPlan(line: line, slots: slots)
        setShifted(plan.shifted.map { views[$0].view })
        return .line(plan.line)
    }

    private func setShifted(_ views: [NSView]) {
        let amount = SidebarDropMap.shiftAmount
        let wanted = Set(views.map(ObjectIdentifier.init))
        for view in shiftedViews where !wanted.contains(ObjectIdentifier(view)) { move(view, by: 0) }
        let current = Set(shiftedViews.map(ObjectIdentifier.init))
        for view in views where !current.contains(ObjectIdentifier(view)) { move(view, by: amount) }
        shiftedViews = views
    }

    private func move(_ view: NSView, by offset: CGFloat) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let from = layer.presentation()?.transform ?? layer.transform
        // Rows inside a folder sit in a non-flipped stack, where positive y moves up.
        let downward: CGFloat = view.superview?.isFlipped == false ? -1 : 1
        let to = CATransform3DMakeTranslation(0, offset * downward, 0)
        layer.transform = to
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "bato-shift")
    }

    private func show(_ shape: SidebarDropTarget.Indicator) {
        if indicator.superview !== self { addSubview(indicator, positioned: .above, relativeTo: nil) }
        let color = SidebarStyle.vivid(accent)
        let shape = applyShift(for: shape)
        switch shape {
        case .line(let frame):
            indicator.frame = frame
            indicator.layer?.cornerRadius = min(frame.width, frame.height) / 2
            indicator.layer?.backgroundColor = color.cgColor
            indicator.layer?.borderWidth = 0
        case .highlight(let frame):
            indicator.frame = frame
            indicator.layer?.cornerRadius = SidebarMetrics.cornerRadius
            indicator.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
            indicator.layer?.borderColor = color.cgColor
            indicator.layer?.borderWidth = 1.5
        }
        indicator.isHidden = false
    }

    private func clear() {
        pending = nil
        indicator.isHidden = true
        setShifted([])
        favoritesZone?.isTargeted = false
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { clear() }
    override func draggingEnded(_ sender: any NSDraggingInfo) { clear() }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { pending != nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { clear() }
        guard let id = entryID(sender), let target = pending else { return false }
        return performDrop?(id, target) ?? false
    }
}

/// A dashed rounded target shown at the top of the sidebar while a tab is dragged and there are no Essentials.
@MainActor
final class FavoritesDropZone: AdaptiveSidebarView {
    var isTargeted = false { didSet { if isTargeted != oldValue { needsDisplay = true } } }
    private let label = NSTextField(labelWithString: "Drop to add to Favorites")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityIdentifier("bato-favorites-drop-zone")
        setAccessibilityLabel("Drop to add to Favorites")
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        NSColor.secondaryLabelColor.withAlphaComponent(isTargeted ? 0.9 : 0.5).setStroke()
        path.stroke()
    }
}

/// Owns drag sessions for sidebar rows; it holds no state so a re-render mid-drag cannot orphan it.
@MainActor
final class SidebarEntryDragSource: NSObject, NSDraggingSource {
    private weak var draggedRow: NSView?

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    var onEnded: (() -> Void)?

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedRow?.alphaValue = 1
        draggedRow = nil
        onEnded?()
    }

    func begin(entryID: UUID, row: NSView, event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(entryID.uuidString, forType: .batoEntry)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let lift: CGFloat = 8
        let image = Self.liftedImage(of: row, margin: lift)
        dragging.setDraggingFrame(row.bounds.insetBy(dx: -lift, dy: -lift), contents: image)
        row.beginDraggingSession(with: [dragging], event: event, source: self)
        row.alphaValue = 0.35
        draggedRow = row
    }

    private static func liftedImage(of row: NSView, margin: CGFloat) -> NSImage {
        let snapshot = row.bitmapImageRepForCachingDisplay(in: row.bounds)
        if let snapshot { row.cacheDisplay(in: row.bounds, to: snapshot) }
        let size = NSSize(width: row.bounds.width + margin * 2, height: row.bounds.height + margin * 2)
        let image = NSImage(size: size)
        image.lockFocus()
        let body = NSRect(x: margin, y: margin, width: row.bounds.width, height: row.bounds.height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 1), xRadius: SidebarMetrics.cornerRadius, yRadius: SidebarMetrics.cornerRadius).fill()
        NSGraphicsContext.restoreGraphicsState()
        snapshot?.draw(in: body)
        image.unlockFocus()
        return image
    }
}
