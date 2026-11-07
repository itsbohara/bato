import AppKit
import BatoCore

/// The downloads list opened from the sidebar button: newest first, with progress, pause/resume,
/// cancel, Show in Finder and drag-out of finished files. Rebuilt from the model on every change.
@MainActor
final class DownloadsPopover: NSObject, NSPopoverDelegate {
    private let controller: DownloadsController
    private let popover = NSPopover()
    private let list = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No downloads yet")
    private var profileKey = ""
    private var listHeightLimit: NSLayoutConstraint?
    /// Fixed rows of the popover around the list: header, spacing and insets.
    private static let chromeHeight: CGFloat = 60

    var isShown: Bool { popover.isShown }

    init(controller: DownloadsController) {
        self.controller = controller
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = makeContent()
    }

    func toggle(from button: NSView, profileKey: String) {
        if popover.isShown { popover.performClose(nil); return }
        self.profileKey = profileKey
        let room = Self.room(around: button)
        let list = SidebarStyle.downloadsPopoverMaxListHeight
        listHeightLimit?.constant = max(80, min(list, room.height - Self.chromeHeight))
        reload()
        controller.markSeen(profileKey)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: room.edge)
        fitToList()
    }

    /// The side of the button with more screen space, and how much of it there is, so the popover
    /// is never cut off by the screen edge or the bottom of the window.
    private static func room(around button: NSView) -> (edge: NSRectEdge, height: CGFloat) {
        guard let window = button.window else { return (.maxY, SidebarStyle.downloadsPopoverMaxListHeight) }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let below = frame.minY - visible.minY
        let above = visible.maxY - frame.maxY
        let visuallyBelow: NSRectEdge = button.isFlipped ? .maxY : .minY
        let visuallyAbove: NSRectEdge = button.isFlipped ? .minY : .maxY
        return below >= above ? (visuallyBelow, below) : (visuallyAbove, above)
    }

    /// NSPopover keeps the largest size it has had; refit so the popover shrinks with its list.
    private func fitToList() {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = NSSize(width: SidebarStyle.downloadsPopoverWidth, height: view.fittingSize.height)
        if popover.contentSize != size { popover.contentSize = size }
    }

    func reload() {
        guard popover.isShown || list.arrangedSubviews.isEmpty else { return }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = controller.model.items(for: profileKey)
        emptyLabel.isHidden = !items.isEmpty
        for item in items {
            let row = DownloadRow(item: item) { [weak self] action in self?.controller.perform(action, on: item) }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if popover.isShown { fitToList() }
    }

    func updateProfile(_ key: String) {
        guard key != profileKey else { return }
        profileKey = key
        if popover.isShown { popover.performClose(nil) }
    }

    private func makeContent() -> NSViewController {
        let heading = NSTextField(labelWithString: "Downloads")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearFinished))
        clear.isBordered = false
        clear.font = .systemFont(ofSize: 12)
        clear.contentTintColor = .secondaryLabelColor
        clear.setAccessibilityIdentifier("bato-downloads-clear")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [heading, spacer, clear])
        header.orientation = .horizontal

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        let flipped = FlippedView()
        flipped.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            list.topAnchor.constraint(equalTo: flipped.topAnchor),
            list.bottomAnchor.constraint(equalTo: flipped.bottomAnchor)
        ])
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = flipped
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let content = NSStackView(views: [header, emptyLabel, scroll])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        content.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -24).isActive = true
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -24).isActive = true

        let host = NSViewController()
        let view = NSView()
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: SidebarStyle.downloadsPopoverWidth)
        ])
        let limit = scroll.heightAnchor.constraint(lessThanOrEqualToConstant: SidebarStyle.downloadsPopoverMaxListHeight)
        limit.isActive = true
        listHeightLimit = limit
        let listHeight = scroll.heightAnchor.constraint(equalTo: flipped.heightAnchor)
        listHeight.priority = .defaultHigh
        listHeight.isActive = true
        host.view = view
        return host
    }

    @objc private func clearFinished() {
        controller.clearFinished(for: profileKey)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class DownloadRow: NSView, NSDraggingSource {
    private let item: DownloadItem
    private let act: (DownloadAction) -> Void
    private var tracking: NSTrackingArea?
    private var hovered = false {
        didSet {
            refreshFill()
            actions.isHidden = !hovered && !item.state.isActive
        }
    }

    override func viewDidChangeEffectiveAppearance() { refreshFill() }

    private func refreshFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = SidebarStyle.rowFill(selected: false, hovered: hovered, tile: false)?.cgColor
        }
    }
    private let actions = NSStackView()

    init(item: DownloadItem, act: @escaping (DownloadAction) -> Void) {
        self.item = item
        self.act = act
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        build()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, item.canOpen { act(.open) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard item.canOpen, let url = item.fileURL else { return }
        let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        dragItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    private func build() {
        let icon = NSImageView(image: item.fileURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .data))
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let name = NSTextField(labelWithString: item.filename)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        let status = NSTextField(labelWithString: DownloadFormat.status(item))
        status.font = .systemFont(ofSize: 11)
        status.textColor = item.state == .failed || item.warning != .none ? .systemRed : .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        var text: [NSView] = [name, status]
        if item.state.isActive {
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.controlSize = .small
            bar.isIndeterminate = item.fraction == nil
            bar.minValue = 0
            bar.maxValue = 1
            bar.doubleValue = item.fraction ?? 0
            if bar.isIndeterminate { bar.startAnimation(nil) }
            text.insert(bar, at: 1)
        }
        if item.warning != .none {
            let decision = NSStackView(views: [
                DownloadTextButton(title: "Keep", id: "bato-download-keep") { [act] in act(.keep) },
                DownloadTextButton(title: "Discard", id: "bato-download-discard") { [act] in act(.discard) }
            ])
            decision.orientation = .horizontal
            decision.spacing = 6
            text.append(decision)
        }
        let textStack = NSStackView(views: text)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        text.filter { !($0 is NSStackView) }.forEach { $0.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true }

        actions.orientation = .horizontal
        actions.spacing = 2
        for spec in actionSpecs() {
            let button = DownloadActionButton(symbol: spec.symbol, label: spec.label) { [act] in act(spec.action) }
            actions.addArrangedSubview(button)
        }
        actions.isHidden = !item.state.isActive

        let row = NSStackView(views: [icon, textStack, actions])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func actionSpecs() -> [(action: DownloadAction, symbol: String, label: String)] {
        if item.warning != .none { return [] }
        return switch item.state {
        case .inProgress: [(.pause, "pause.fill", "Pause"), (.cancel, "xmark", "Cancel")]
        case .paused: [(.resume, "play.fill", "Resume"), (.cancel, "xmark", "Cancel")]
        case .completed where item.canOpen: [(.showInFinder, "magnifyingglass", "Show in Finder"), (.remove, "xmark", "Remove from list")]
        case .failed where item.canResume: [(.resume, "arrow.clockwise", "Resume"), (.remove, "xmark", "Remove from list")]
        default: [(.remove, "xmark", "Remove from list")]
        }
    }
}

private final class DownloadActionButton: NSButton {
    private let invoke: () -> Void

    init(symbol: String, label: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(frame: .zero)
        image = sidebarSymbol(symbol, size: 11, weight: .semibold)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .recessed
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(run)
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }
    @objc private func run() { invoke() }
}

private final class DownloadTextButton: NSButton {
    private let invoke: () -> Void

    init(title: String, id: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: 11, weight: .medium)
        target = self
        action = #selector(run)
        setAccessibilityIdentifier(id)
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }
    @objc private func run() { invoke() }
}
