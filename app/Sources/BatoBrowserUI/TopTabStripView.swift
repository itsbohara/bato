import AppKit
import BatoCore

/// One tab of the top strip, as the strip draws it.
struct TopTabModel {
    let id: UUID
    let title: String
    let url: URL
    let icon: NSImage?
    let section: BrowserState.SidebarSection
    let isIconOnly: Bool
    let isSelected: Bool
    let canClose: Bool
}

/// The horizontal tab strip of the top layout. It paints nothing itself: the workspace root behind it
/// carries the Space theme, so the strip always wears the active Space's colours.
@MainActor
final class TopTabStripView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    let switcherButton = NSButton(frame: .zero)
    private let newTabButton = NSButton(frame: .zero)
    private let splitButton = NSButton(frame: .zero)
    private var tabViews: [TopTabView] = []
    private var dragged: TopTabView?
    private var dragSlot: Int?
    private let indicator = NSView()
    private var pending: [TopTabModel]?

    var select: (UUID) -> Void = { _ in }
    var close: (UUID) -> Void = { _ in }
    var newTab: () -> Void = {}
    var showSplitMenu: (NSView) -> Void = { _ in }
    var menuFor: (UUID) -> NSMenu? = { _ in nil }
    /// Called with the dragged tab, its section and the gap it was dropped into among that section's tabs.
    var reorder: (UUID, BrowserState.SidebarSection, Int) -> Void = { _, _, _ in }
    var canReorder: (UUID, BrowserState.SidebarSection) -> Bool = { _, _ in false }
    var canSplit = false { didSet { splitButton.isEnabled = canSplit } }

    private static let controlSide: CGFloat = 28
    private static let edgeInset: CGFloat = 10
    private static let switcherMaxWidth: CGFloat = 150

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configureSwitcher()
        configureControl(newTabButton, symbol: "plus", label: "New Tab", identifier: "bato-strip-new-tab", action: #selector(newTabClicked))
        configureControl(splitButton, symbol: "rectangle.split.2x1", label: "Split view", identifier: "bato-toolbar-split", action: #selector(splitClicked))
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 1
        indicator.isHidden = true
        [switcherButton, newTabButton, splitButton, indicator].forEach(addSubview)
        setAccessibilityIdentifier("bato-top-tab-strip")
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    private func configureSwitcher() {
        switcherButton.isBordered = false
        switcherButton.bezelStyle = .recessed
        switcherButton.font = .systemFont(ofSize: 13, weight: .semibold)
        switcherButton.contentTintColor = .labelColor
        switcherButton.alignment = .left
        switcherButton.lineBreakMode = .byTruncatingTail
        switcherButton.imagePosition = .imageLeading
        switcherButton.imageHugsTitle = true
        switcherButton.setAccessibilityLabel("Current workspace")
        switcherButton.setAccessibilityIdentifier("bato-space-name")
    }

    private func configureControl(_ button: NSButton, symbol: String, label: String, identifier: String, action: Selector) {
        button.image = sidebarSymbol(symbol, size: 13)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .recessed
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        button.toolTip = label
        button.target = self
        button.action = action
    }

    @objc private func newTabClicked() { newTab() }
    @objc private func splitClicked() { showSplitMenu(splitButton) }

    func apply(_ models: [TopTabModel]) {
        guard dragged == nil else { pending = models; return }
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews = models.map { model in
            let view = TopTabView(model: model)
            view.onSelect = { [weak self] in self?.select(model.id) }
            view.onClose = { [weak self] in self?.close(model.id) }
            view.menuProvider = { [weak self] in self?.menuFor(model.id) }
            view.onDrag = { [weak self] view, event in self?.drag(view, event: event) }
            view.onDrop = { [weak self] view in self?.drop(view) }
            addSubview(view, positioned: .below, relativeTo: indicator)
            return view
        }
        needsLayout = true
    }

    /// The x where the traffic lights end, so the Space switcher starts clear of them.
    private var lightsEnd: CGFloat {
        guard let window, let zoom = window.standardWindowButton(.zoomButton) else { return 78 }
        return convert(zoom.convert(zoom.bounds, to: nil), from: nil).maxX
    }

    private var tabRegion: ClosedRange<CGFloat> {
        let start = switcherButton.frame.maxX + 10
        let end = splitButton.frame.minX - 6 - Self.controlSide - 6
        return start...max(start, end)
    }

    override func layout() {
        super.layout()
        let side = Self.controlSide
        let midY = TopTabStrip.rowCenterY
        splitButton.frame = NSRect(x: bounds.width - Self.edgeInset - side, y: midY - side / 2, width: side, height: side)
        newTabButton.frame = NSRect(x: splitButton.frame.minX - 6 - side, y: midY - side / 2, width: side, height: side)
        let switcherWidth = min(Self.switcherMaxWidth, ceil(switcherButton.intrinsicContentSize.width))
        switcherButton.frame = NSRect(x: lightsEnd + SidebarMetrics.trafficLightGap, y: midY - side / 2, width: switcherWidth, height: side)
        let items = tabViews.map { TopTabItem(id: $0.model.id, isIconOnly: $0.model.isIconOnly) }
        let region = tabRegion
        let frames = TopTabStrip.frames(for: items, from: region.lowerBound, to: region.upperBound)
        for (view, frame) in zip(tabViews, frames) where view !== dragged {
            view.frame = frame
            view.isHidden = frame.minX >= region.upperBound
        }
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

    private func drag(_ view: TopTabView, event: NSEvent) {
        guard canReorder(view.model.id, view.model.section) else { return }
        if dragged == nil {
            dragged = view
            view.alphaValue = 0.7
            addSubview(view, positioned: .above, relativeTo: nil)
        }
        let x = convert(event.locationInWindow, from: nil).x
        let region = tabRegion
        view.frame.origin.x = min(max(x - view.frame.width / 2, region.lowerBound), region.upperBound - view.frame.width)
        let siblings = tabViews.filter { $0.model.section == view.model.section }
        let slot = TopTabStrip.insertionSlot(atX: view.frame.midX, among: siblings.map(\.slotFrame))
        dragSlot = slot
        let marker = slot < siblings.count ? siblings[slot].slotFrame.minX - TopTabStrip.gap / 2
                                           : (siblings.last?.slotFrame.maxX ?? 0) + TopTabStrip.gap / 2
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        indicator.frame = NSRect(x: marker - 1, y: view.frame.minY, width: 2, height: view.frame.height)
        indicator.isHidden = false
    }

    private func drop(_ view: TopTabView) {
        guard dragged === view else { return }
        let slot = dragSlot
        dragged = nil
        dragSlot = nil
        view.alphaValue = 1
        indicator.isHidden = true
        if let slot { reorder(view.model.id, view.model.section, slot) }
        if let pending {
            self.pending = nil
            apply(pending)
        }
        needsLayout = true
    }
}

/// A tab's resting frame, so a dragged tab is measured against where the others sit rather than where it floats.
private extension TopTabView {
    var slotFrame: NSRect { restingFrame }
}

@MainActor
private final class TopTabView: NSView {
    let model: TopTabModel
    // The strip sits in the titlebar band, where AppKit would otherwise turn a press into a window move.
    override var mouseDownCanMoveWindow: Bool { false }
    var onSelect: () -> Void = {}
    var onClose: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }
    var onDrag: (TopTabView, NSEvent) -> Void = { _, _ in }
    var onDrop: (TopTabView) -> Void = { _ in }
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(frame: .zero)
    private var hovered = false { didSet { needsLayout = true; needsDisplay = true } }
    private var tracking: NSTrackingArea?
    private var pressOrigin: NSPoint?
    private var didDrag = false
    private(set) var restingFrame = NSRect.zero

    override var frame: NSRect { didSet { if !didDrag { restingFrame = frame } } }
    override var isFlipped: Bool { true }

    init(model: TopTabModel) {
        self.model = model
        super.init(frame: .zero)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.image = model.icon ?? SidebarStyle.letterIcon(for: model.title, url: model.url, size: SidebarStyle.rowIconSize)
        titleLabel.stringValue = model.title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: model.isSelected ? .semibold : .regular)
        titleLabel.textColor = model.isSelected ? .labelColor : .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isHidden = model.isIconOnly
        closeButton.image = sidebarSymbol("xmark", size: 9)
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .recessed
        closeButton.focusRingType = .none
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.setAccessibilityLabel("Close \(model.title)")
        closeButton.setAccessibilityIdentifier("bato-close-\(model.id.uuidString)")
        [iconView, titleLabel, closeButton].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(model.title)
        setAccessibilityValue(model.isSelected)
        setAccessibilityIdentifier("bato-page-\(model.id.uuidString)")
        toolTip = model.title
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    @objc private func closeClicked() { onClose() }

    override func accessibilityPerformPress() -> Bool { onSelect(); return true }

    private var showsClose: Bool { !model.isIconOnly && model.canClose && (hovered || model.isSelected) && bounds.width >= 72 }

    override func layout() {
        super.layout()
        let icon = SidebarStyle.rowIconSize
        let leading: CGFloat = model.isIconOnly ? (bounds.width - icon) / 2 : (bounds.width < 56 ? (bounds.width - icon) / 2 : 10)
        iconView.frame = NSRect(x: leading, y: (bounds.height - icon) / 2, width: icon, height: icon)
        closeButton.isHidden = !showsClose
        closeButton.frame = NSRect(x: bounds.width - 24, y: (bounds.height - 20) / 2, width: 20, height: 20)
        let titleStart = leading + icon + 7
        let titleEnd = showsClose ? bounds.width - 26 : bounds.width - 8
        titleLabel.isHidden = model.isIconOnly || titleEnd - titleStart < 24
        let height = ceil(titleLabel.intrinsicContentSize.height)
        titleLabel.frame = NSRect(x: titleStart, y: (bounds.height - height) / 2, width: max(0, titleEnd - titleStart), height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        guard let fill = SidebarStyle.rowFill(selected: model.isSelected, hovered: hovered, tile: false) else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: SidebarMetrics.cornerRadius, yRadius: SidebarMetrics.cornerRadius).fill()
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin else { return }
        if !didDrag, abs(event.locationInWindow.x - origin.x) < 4 { return }
        didDrag = true
        onDrag(self, event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressOrigin = nil }
        guard didDrag else { return onSelect() }
        didDrag = false
        onDrop(self)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return super.otherMouseUp(with: event)
        }
        onClose()
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }
}
