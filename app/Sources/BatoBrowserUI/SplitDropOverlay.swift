import AppKit
import BatoCore

/// Left and right drop areas shown over the page card while a sidebar tab is dragged. The page is a native
/// engine view that never sees the drag, so this view sits above it and is the destination while armed.
@MainActor
final class SplitDropOverlay: NSView {
    /// The page card in this view's flipped coordinates.
    var cardRect: NSRect = .zero { didSet { layoutZones(animated: false) } }
    var onDrop: ((UUID, SplitSide) -> Bool)?
    private(set) var isArmed = false
    private var expanded = false
    private var hovered: SplitSide?
    private var zones: [SplitSide: SplitDropZoneView] = [:]

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        isHidden = true
        registerForDraggedTypes([.batoEntry])
        for side in SplitDropZones.sides {
            let zone = SplitDropZoneView(side: side)
            zones[side] = zone
            addSubview(zone)
        }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func arm() {
        isArmed = true
        expanded = false
        hovered = nil
        isHidden = false
        layoutZones(animated: false)
        zones.values.forEach { $0.alphaValue = 0 }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; zones.values.forEach { $0.animator().alphaValue = 1 } }
    }

    func disarm() {
        guard isArmed else { return }
        isArmed = false
        isHidden = true
    }

    private func layoutZones(animated: Bool) {
        for (side, zone) in zones {
            guard let frame = SplitDropZones.frame(of: side, in: cardRect, expanded: expanded, hovered: hovered == side) else { continue }
            zone.isTargeted = hovered == side
            if animated {
                NSAnimationContext.runAnimationGroup { $0.duration = 0.2; zone.animator().frame = frame }
            } else {
                zone.frame = frame
            }
        }
    }

    private func entryID(_ sender: any NSDraggingInfo) -> UUID? {
        sender.draggingPasteboard.string(forType: .batoEntry).flatMap(UUID.init(uuidString:))
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let (wasExpanded, wasHovered) = (expanded, hovered)
        expanded = cardRect.contains(point)
        hovered = SplitDropZones.side(at: point, in: cardRect, expanded: expanded)
        if wasExpanded != expanded || wasHovered != hovered { layoutZones(animated: true) }
        return hovered == nil ? [] : .move
    }

    private func collapse() {
        hovered = nil
        expanded = false
        layoutZones(animated: true)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { collapse() }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { hovered != nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let id = entryID(sender), let side = hovered else { return false }
        return onDrop?(id, side) ?? false
    }
}

@MainActor
private final class SplitDropZoneView: NSView {
    var isTargeted = false {
        didSet {
            guard isTargeted != oldValue else { return }
            let tint = isTargeted ? Self.targetAccent : NSColor.white.withAlphaComponent(0.6)
            icon.contentTintColor = tint
            label.textColor = tint
            needsDisplay = true
        }
    }
    private let icon = NSImageView()
    private let label: NSTextField

    private static let targetAccent = NSColor(srgbRed: 0.84, green: 0.50, blue: 0, alpha: 1)
    private static let targetFill = NSColor(srgbRed: 0.24, green: 0.18, blue: 0.12, alpha: 0.96)

    override var isFlipped: Bool { true }

    init(side: SplitSide) {
        label = NSTextField(labelWithString: side == .left ? "Add left split" : "Add right split")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        icon.image = NSImage(systemSymbolName: side == .left ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled",
                             accessibilityDescription: nil)
        icon.contentTintColor = .white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white.withAlphaComponent(0.6)
        [icon, label].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -4),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: centerYAnchor, constant: 8)
        ])
        setAccessibilityIdentifier("bato-split-drop-\(side.rawValue)")
        setAccessibilityLabel(label.stringValue)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = SplitDropZones.cornerRadius
        (isTargeted ? Self.targetFill : NSColor(white: 0.13, alpha: 0.96)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let dashed = NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), xRadius: radius - 8, yRadius: radius - 8)
        dashed.lineWidth = 1.5
        dashed.setLineDash([5, 4], count: 2, phase: 0)
        (isTargeted ? Self.targetAccent : NSColor.white.withAlphaComponent(0.4)).setStroke()
        dashed.stroke()
    }
}
