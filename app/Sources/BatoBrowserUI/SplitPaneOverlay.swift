import AppKit
import BatoCore

public enum PaneNavigationAction: Int32, Sendable {
    case back = 0, forward, reload, stop
}

public struct PaneNavigationState: Equatable, Sendable {
    public var canGoBack = false
    public var canGoForward = false
    public var isLoading = false
    public init(canGoBack: Bool = false, canGoForward: Bool = false, isLoading: Bool = false) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
    /// Decodes the client's bit set: 1 back, 2 forward, 4 loading.
    public init(bits: Int32) {
        self.init(canGoBack: bits & 1 != 0, canGoForward: bits & 2 != 0, isLoading: bits & 4 != 0)
    }
}

public struct SplitPaneState {
    public var entryID: UUID
    public var title: String
    public var url: URL?
    public var isFocused: Bool
    public var navigation: PaneNavigationState
}

public struct SplitPaneActions {
    public var focus: (UUID) -> Void
    public var close: (UUID) -> Void
    public var navigate: (UUID, PaneNavigationAction) -> Void
    public var addSplit: (SplitSide) -> Void
    public var toggleSidebar: () -> Void
}

/// The menu behind every split button: one item per side, each with its own glyph.
@MainActor func makeSplitMenu(isEnabled: Bool, handler: @escaping (SplitSide) -> Void) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for side in [SplitSide.right, .left, .top, .bottom] {
        let item = ActionMenuItem(title: side.title) { handler(side) }
        item.image = sidebarSymbol(side.symbolName, size: 13)
        item.isEnabled = isEnabled
        item.setAccessibilityIdentifier("bato-add-split-\(side.rawValue)")
        menu.addItem(item)
    }
    return menu
}

/// One compact toolbar row above a split pane. A focused pane shows every control; an unfocused
/// one shows only dimmed back/forward, its host and close until the pointer rests on the row.
@MainActor final class SplitPaneToolbarView: NSView {
    private let back = NSButton(frame: .zero)
    private let forward = NSButton(frame: .zero)
    private let reload = NSButton(frame: .zero)
    private let splitButton = NSButton(frame: .zero)
    private let close = NSButton(frame: .zero)
    private let linkGlyph = NSImageView(frame: .zero)
    private let host = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private(set) var state: SplitPaneState?
    private var actions: SplitPaneActions?
    private var splitMenuEnabled = true
    /// Space taken by the traffic lights and the show-sidebar button when this row starts at the window's corner.
    var leadingInset: CGFloat = 0 { didSet { needsLayout = true } }
    let paneIndex: Int

    init(paneIndex: Int) {
        self.paneIndex = paneIndex
        super.init(frame: .zero)
        wantsLayer = true
        for (button, symbol, label, identifier) in [
            (back, "chevron.left", "Back", "back"), (forward, "chevron.right", "Forward", "forward"),
            (reload, "arrow.clockwise", "Reload", "reload"), (splitButton, "rectangle.split.2x1", "Split view", "split"),
            (close, "xmark", "Close pane", "close")] {
            button.image = sidebarSymbol(symbol, size: 12, weight: .medium)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.bezelStyle = .recessed
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.setAccessibilityIdentifier("bato-pane-\(paneIndex)-\(identifier)")
            button.target = self
            addSubview(button)
        }
        back.action = #selector(goBack)
        forward.action = #selector(goForward)
        reload.action = #selector(reloadOrStop)
        splitButton.action = #selector(showSplitMenu)
        close.action = #selector(closePane)
        linkGlyph.image = sidebarSymbol("link", size: 10, weight: .medium)
        linkGlyph.contentTintColor = .tertiaryLabelColor
        host.font = .systemFont(ofSize: 12, weight: .medium)
        host.textColor = .labelColor
        host.lineBreakMode = .byTruncatingTail
        host.alignment = .center
        host.setAccessibilityIdentifier("bato-pane-\(paneIndex)-host")
        addSubview(linkGlyph)
        addSubview(host)
        setAccessibilityIdentifier("bato-pane-\(paneIndex)-toolbar")
        AppearanceWatcher.start()
        NotificationCenter.default.addObserver(self, selector: #selector(restyle),
                                               name: AppearanceWatcher.didChange, object: nil)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle() }

    @objc private func restyle() {
        let dark = effectiveAppearance.isDark
        layer?.backgroundColor = (dark ? NSColor(white: 0.145, alpha: 1) : NSColor(white: 0.985, alpha: 1)).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    /// A click on empty toolbar space moves focus into the pane, like a click on its page.
    override func mouseDown(with event: NSEvent) {
        if let id = state?.entryID { actions?.focus(id) }
    }

    /// Chromium's content view takes mouse events over its own area before subviews see them, so the overlay
    /// forwards a click here: a visible enabled control acts, empty space focuses the pane.
    func handleClick(at point: NSPoint) {
        for control in [back, forward, reload, splitButton, close] where !control.isHidden && control.isEnabled &&
            control.alphaValue > 0.05 && control.frame.contains(point) {
            // Deferred: a menu or close started inside the event monitor would run its own tracking loop there.
            DispatchQueue.main.async { [weak control] in
                guard let control, let action = control.action else { return }
                NSApp.sendAction(action, to: control.target, from: control)
            }
            return
        }
        if let id = state?.entryID { actions?.focus(id) }
    }

    func setHovered(_ hovered: Bool, animated: Bool = true) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        applyControls(animated: animated)
    }

    func update(_ state: SplitPaneState, actions: SplitPaneActions, splitMenuEnabled: Bool) {
        self.state = state
        self.actions = actions
        self.splitMenuEnabled = splitMenuEnabled
        host.stringValue = Self.displayHost(url: state.url, title: state.title)
        back.isEnabled = state.navigation.canGoBack
        forward.isEnabled = state.navigation.canGoForward
        reload.image = sidebarSymbol(state.navigation.isLoading ? "xmark" : "arrow.clockwise", size: 12, weight: .medium)
        reload.toolTip = state.navigation.isLoading ? "Stop" : "Reload"
        applyControls(animated: false)
        needsLayout = true
    }

    static func displayHost(url: URL?, title: String) -> String {
        guard let host = url?.host, !host.isEmpty else { return title }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Controls that fade with focus and hover share one opacity so a hover reads as the row "waking up".
    private func applyControls(animated: Bool) {
        guard let state else { return }
        let visible = SplitPaneControls.visible(focused: state.isFocused, hovered: isHovered)
        let dimmed = SplitPaneControls.dimmed(focused: state.isFocused)
        let toggles: [(NSView, SplitPaneControls)] = [(reload, .reload), (splitButton, .splitMenu)]
        let dimTargets: [(NSButton, SplitPaneControls)] = [(back, .back), (forward, .forward)]
        let apply = {
            for (view, control) in toggles {
                let shown = visible.contains(control)
                view.animator().alphaValue = shown ? 1 : 0
            }
            for (button, control) in dimTargets {
                button.animator().alphaValue = dimmed.contains(control) ? 0.4 : 1
            }
        }
        for (view, control) in toggles {
            if visible.contains(control) { view.isHidden = false }
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = SplitPaneChrome.hoverFadeDuration
                apply()
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let state = self.state else { return }
                    let current = SplitPaneControls.visible(focused: state.isFocused, hovered: self.isHovered)
                    for (view, control) in toggles { view.isHidden = !current.contains(control) }
                }
            })
        } else {
            for (view, control) in toggles {
                view.alphaValue = visible.contains(control) ? 1 : 0
                view.isHidden = !visible.contains(control)
            }
            for (button, control) in dimTargets { button.alphaValue = dimmed.contains(control) ? 0.4 : 1 }
        }
        splitButton.isEnabled = splitMenuEnabled
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 26
        let y = (bounds.height - side) / 2
        var x = 8 + leadingInset
        for button in [back, forward, reload] {
            button.frame = NSRect(x: x, y: y, width: side, height: side)
            x += side + 2
        }
        var trailing = bounds.width - 8
        close.frame = NSRect(x: trailing - side, y: y, width: side, height: side)
        trailing -= side + 2
        splitButton.frame = NSRect(x: trailing - side, y: y, width: side, height: side)
        trailing -= side + 2
        let available = max(0, trailing - x)
        let natural = (host.stringValue as NSString).size(withAttributes: [.font: host.font ?? .systemFont(ofSize: 12)]).width
        let textWidth = min(ceil(natural) + 10, max(0, available - 20))
        let groupWidth = 16 + textWidth
        // Centre on the pane, then keep clear of the controls on either side.
        var groupX = (bounds.width - groupWidth) / 2
        groupX = min(max(groupX, x), max(x, trailing - groupWidth))
        linkGlyph.frame = NSRect(x: groupX, y: (bounds.height - 12) / 2, width: 12, height: 12)
        host.frame = NSRect(x: groupX + 16, y: (bounds.height - 16) / 2, width: textWidth, height: 16)
    }

    @objc private func goBack() { act(.back) }
    @objc private func goForward() { act(.forward) }
    @objc private func reloadOrStop() { act(state?.navigation.isLoading == true ? .stop : .reload) }
    private func act(_ action: PaneNavigationAction) {
        if let id = state?.entryID { actions?.navigate(id, action) }
    }
    @objc private func closePane() {
        if let id = state?.entryID { actions?.close(id) }
    }
    @objc private func showSplitMenu() {
        guard let actions, let id = state?.entryID else { return }
        // Focus first so the chosen split is added beside this pane's page.
        actions.focus(id)
        let menu = makeSplitMenu(isEnabled: splitMenuEnabled) { side in actions.addSplit(side) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: splitButton.bounds.height + 4), in: splitButton)
    }
}

/// Native toolbar rows over a displayed split pair. It is transparent except for the rows, so Chromium's
/// pages and the card's rounded cut-outs show through; the card view draws the outline around the focused pane.
@MainActor public final class SplitPaneOverlayView: NSView {
    public var provider: () -> [SplitPaneState] = { [] }
    public var actions = SplitPaneActions(focus: { _ in }, close: { _ in }, navigate: { _, _ in },
                                          addSplit: { _ in }, toggleSidebar: {})
    /// The sidebar is hidden, so the first pane's row also clears the traffic lights and show-sidebar button.
    public var sidebarHidden = false { didSet { needsLayout = true } }
    public var tabLayout = TabLayout.sidebar { didSet { needsLayout = true } }
    public private(set) var paneFrames: [NSRect] = []
    private var toolbars: [SplitPaneToolbarView] = []
    private var poll: Timer?
    private var clickMonitor: Any?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        // Below the card's gutter (zPosition 1000) so its rounded cut-outs clip the rows' corners.
        layer?.zPosition = 999
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    deinit { MainActor.assumeIsolated { poll?.invalidate() } }

    public override var isFlipped: Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Pane frames in this view's flipped coordinates, including each pane's toolbar band; empty hides the rows.
    public func apply(frames: [NSRect]) {
        paneFrames = frames
        isHidden = frames.isEmpty
        poll?.invalidate()
        poll = nil
        if frames.isEmpty, let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if !frames.isEmpty, clickMonitor == nil {
            // AppKit delivers local monitors on the main thread.
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                nonisolated(unsafe) let unsafeEvent = event
                let handled = MainActor.assumeIsolated { self?.route(unsafeEvent) == true }
                return handled ? nil : event
            }
        }
        if frames.isEmpty {
            toolbars.forEach { $0.removeFromSuperview() }
            toolbars.removeAll()
            return
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    public func refresh() {
        let panes = provider()
        guard !paneFrames.isEmpty, panes.count == paneFrames.count else {
            if panes.count != paneFrames.count, !paneFrames.isEmpty { toolbars.forEach { $0.isHidden = true } }
            return
        }
        while toolbars.count < panes.count {
            let bar = SplitPaneToolbarView(paneIndex: toolbars.count)
            toolbars.append(bar)
            addSubview(bar)
        }
        for (index, pane) in panes.enumerated() {
            let bar = toolbars[index]
            bar.isHidden = false
            let frame = SplitPaneChrome.toolbarFrame(ofPane: paneFrames[index])
            if bar.frame != frame { bar.frame = frame }
            bar.leadingInset = leadingInset(forPane: index, frame: frame)
            bar.update(pane, actions: actions, splitMenuEnabled: true)
        }
    }

    /// True when the click landed on a pane toolbar and was handled here.
    private func route(_ event: NSEvent) -> Bool {
        guard !isHidden, event.window === window, window?.attachedSheet == nil else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard let bar = toolbars.first(where: { !$0.isHidden && $0.frame.contains(point) }) else { return false }
        bar.handleClick(at: bar.convert(point, from: self))
        return true
    }

    private func leadingInset(forPane index: Int, frame: NSRect) -> CGFloat {
        guard SplitPaneChrome.clearsTrafficLights(paneIndex: index, layout: tabLayout, sidebarHidden: sidebarHidden),
              let window, let zoom = window.standardWindowButton(.zoomButton) else { return 0 }
        let lightsEnd = convert(zoom.convert(zoom.bounds, to: nil), from: nil).maxX
        let slot = tabLayout == .sidebar ? SidebarMetrics.trafficLightGap + SidebarMetrics.revealButtonSide + 4
                                         : SidebarMetrics.trafficLightGap
        return max(0, lightsEnd + slot - frame.minX - 8)
    }

    /// Test hook: the rows currently shown, in pane order.
    var toolbarViews: [SplitPaneToolbarView] { toolbars }
}
