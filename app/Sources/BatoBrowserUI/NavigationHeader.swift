import AppKit
import BatoRuntime

struct NavigationHeaderModel: Equatable {
    var url: URL?
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var canToggleLoading = false
    var canEditAddress = false
    var failureCode: Int32?

    /// The host is a label, never a security indicator: Chromium's own origin UI stays authoritative.
    var host: String {
        guard let host = url?.host, !host.isEmpty else { return url?.absoluteString ?? "No page" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Back, Forward and Reload/Stop for the sidebar's top row, and the address pill below it.
@MainActor
final class NavigationHeader {
    var onCommand: ((PageNavigationCommand) -> Void)?
    var onEditAddress: (() -> Void)?
    let controls: NSStackView
    let pill = NavigationPill()
    private let back = NavigationButton(symbol: "chevron.left", label: "Go back", identifier: "bato-nav-back")
    private let forward = NavigationButton(symbol: "chevron.right", label: "Go forward", identifier: "bato-nav-forward")
    private let reload = NavigationButton(symbol: "arrow.clockwise", label: "Reload page", identifier: "bato-nav-reload")
    private var isLoading = false

    init() {
        controls = NSStackView(views: [back, forward, reload])
        controls.orientation = .horizontal
        controls.spacing = 4
        back.onPress = { [weak self] in self?.onCommand?(.back) }
        forward.onPress = { [weak self] in self?.onCommand?(.forward) }
        reload.onPress = { [weak self] in self?.onCommand?(self?.isLoading == true ? .stop : .reload) }
        pill.onPress = { [weak self] in self?.onEditAddress?() }
    }

    func update(_ model: NavigationHeaderModel, accent: NSColor) {
        isLoading = model.isLoading
        back.isEnabled = model.canGoBack
        forward.isEnabled = model.canGoForward
        reload.isEnabled = model.canToggleLoading
        reload.setSymbol(model.isLoading ? "xmark" : "arrow.clockwise",
                         label: model.isLoading ? "Stop loading" : "Reload page")
        pill.update(model, accent: accent)
    }
}

@MainActor
private final class NavigationButton: NSButton {
    var onPress: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(symbol: String, label: String, identifier: String) {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        target = self
        action = #selector(press)
        setAccessibilityIdentifier(identifier)
        // About a 36pt pitch at the default width; the soft width lets a narrow sidebar squeeze the row.
        let width = widthAnchor.constraint(equalToConstant: 32)
        width.priority = .init(749)
        width.isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setSymbol(symbol, label: label)
        refreshTint()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    override var isEnabled: Bool {
        didSet { refreshTint(); needsDisplay = true }
    }

    func setSymbol(_ name: String, label: String) {
        image = sidebarSymbol(name, size: 17, weight: .light)
        setAccessibilityLabel(label)
        toolTip = label
    }

    private func refreshTint() {
        contentTintColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    @objc private func press() { onPress?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled, hovered || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.14 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
}

@MainActor
final class NavigationPill: AdaptiveSidebarView {
    var onPress: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let progress = CALayer()
    private var model = NavigationHeaderModel()
    private var accent = NSColor.controlAccentColor
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = SidebarMetrics.cornerRadius
        layer?.masksToBounds = true
        layer?.addSublayer(progress)
        progress.isHidden = true
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setAccessibilityElement(false)
        let content = NSStackView(views: [icon, label])
        content.orientation = .horizontal
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 14)
        ])
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("bato-nav-address")
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    // Also the host's native focus target, so it must accept focus even when disabled.
    override var acceptsFirstResponder: Bool { true }
    func update(_ next: NavigationHeaderModel, accent: NSColor) {
        model = next
        self.accent = accent
        label.stringValue = next.host
        label.textColor = .secondaryLabelColor
        let failed = next.failureCode != nil
        icon.image = sidebarSymbol(failed ? "exclamationmark.triangle.fill" : "link", size: 12)
        icon.contentTintColor = failed ? .systemRed : .secondaryLabelColor
        toolTip = [next.url?.absoluteString, next.failureCode.map { "This page failed to load (error \($0))." }]
            .compactMap { $0 }.joined(separator: "\n")
        needsDisplay = true
        needsLayout = true
        noteFocusRingMaskChanged()
    }

    override func accessibilityLabel() -> String? {
        model.failureCode == nil ? "Address" : "Address, this page failed to load"
    }
    override func accessibilityValue() -> Any? { model.url?.absoluteString }
    override func accessibilityHelp() -> String? { "Edit the address of this page" }
    override func isAccessibilityEnabled() -> Bool { model.canEditAddress }
    override func accessibilityPerformPress() -> Bool {
        guard model.canEditAddress else { return false }
        onPress?()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        guard model.canEditAddress else { return }
        pressed = true
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let activate = pressed && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if activate { onPress?() }
    }
    override func keyDown(with event: NSEvent) {
        guard model.canEditAddress, [36, 49, 76].contains(event.keyCode) else { return super.keyDown(with: event) }
        onPress?()
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: SidebarMetrics.cornerRadius, yRadius: SidebarMetrics.cornerRadius).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }

    override func draw(_ dirtyRect: NSRect) {
        let radius = SidebarMetrics.cornerRadius
        let fill: NSColor
        if model.failureCode != nil {
            fill = NSColor.systemRed.withAlphaComponent(0.18)
        } else {
            fill = model.canEditAddress && (pressed || hovered)
                ? NSColor.labelColor.withAlphaComponent(pressed ? 0.13 : 0.1) : .clear
        }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    override func layout() {
        super.layout()
        let width = max(24, bounds.width * 0.35)
        progress.frame = CGRect(x: 0, y: 0, width: width, height: 3)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            progress.backgroundColor = (accent.blended(withFraction: 0.5, of: .labelColor) ?? accent).cgColor
        }
        updateLoadingIndicator()
    }

    /// Progress is unknown, so loading is a sliding segment; Reduce Motion keeps it still.
    private func updateLoadingIndicator() {
        progress.removeAnimation(forKey: "slide")
        progress.isHidden = !model.isLoading
        guard model.isLoading, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = -progress.bounds.width / 2
        slide.toValue = bounds.width + progress.bounds.width / 2
        slide.duration = 1.1
        slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        progress.add(slide, forKey: "slide")
    }
}
