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
    private static let rowGap: CGFloat = 2.5

    static func resolve(point: NSPoint, slots: [SidebarDropSlot], unfiledPinCount: Int) -> SidebarDropTarget? {
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
            case .tile, .folder: return false
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
        case .tile, .folder:
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

    private static func verticalLine(at x: CGFloat, in frame: NSRect) -> NSRect {
        NSRect(x: x - lineThickness / 2, y: frame.minY + 4, width: lineThickness, height: frame.height - 8)
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

    var resolveDrop: ((UUID, NSPoint) -> SidebarDropTarget?)?
    var performDrop: ((UUID, SidebarDropTarget) -> Bool)?
    var accent: NSColor = .controlAccentColor
    private let indicator = NSView()
    private var pending: SidebarDropTarget?

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
        return .move
    }

    private func show(_ shape: SidebarDropTarget.Indicator) {
        if indicator.superview !== self { addSubview(indicator, positioned: .above, relativeTo: nil) }
        let color = SidebarStyle.vivid(accent)
        switch shape {
        case .line(let frame):
            indicator.frame = frame
            indicator.layer?.cornerRadius = SidebarDropMap.lineThickness / 2
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

/// Owns drag sessions for sidebar rows; it holds no state so a re-render mid-drag cannot orphan it.
@MainActor
final class SidebarEntryDragSource: NSObject, NSDraggingSource {
    private weak var draggedRow: NSView?

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedRow?.alphaValue = 1
        draggedRow = nil
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
