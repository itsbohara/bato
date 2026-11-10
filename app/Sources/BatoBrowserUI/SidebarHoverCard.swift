import AppKit

/// What the card for a sidebar row says: the page title and where it lives.
struct SidebarHoverCardContent: Equatable {
    var title: String
    var host: String

    init(title: String, url: URL) {
        let host = (url.host ?? url.absoluteString).replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? host : trimmed
        self.host = host
    }
}

/// A small card beside a hovered sidebar row. It is a non-activating, click-through panel so it can never
/// take focus from the page or catch a click meant for the row.
@MainActor
final class SidebarHoverCard {
    static let delay: TimeInterval = 0.6
    /// The sidebar is on the right, so the card opens over the page on its left.
    var opensTowardsLeft = false
    private var timer: Timer?
    private var panel: NSPanel?
    private var monitor: Any?
    /// Where the pointer was when a click, scroll or key dismissed the card. The row is rebuilt under a
    /// stationary pointer and would otherwise raise the card again straight away.
    private var suppressedAt: NSPoint?

    func schedule(_ content: SidebarHoverCardContent, anchor: NSView) {
        dismiss()
        if let suppressedAt, hypot(NSEvent.mouseLocation.x - suppressedAt.x, NSEvent.mouseLocation.y - suppressedAt.y) < 2 { return }
        suppressedAt = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.suppressedAt = NSEvent.mouseLocation
                self?.dismiss()
            }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.delay, repeats: false) { [weak self, weak anchor] _ in
            MainActor.assumeIsolated {
                guard let self, let anchor else { return }
                self.show(content, anchor: anchor)
            }
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let panel, let parent = panel.parent { parent.removeChildWindow(panel) }
        panel?.orderOut(nil)
        panel = nil
    }

    private static func width(of text: String, font: NSFont?) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 12)]).width) + 2
    }

    private func show(_ content: SidebarHoverCardContent, anchor: NSView) {
        guard let window = anchor.window, window.isKeyWindow, window.attachedSheet == nil else { return dismiss() }
        let title = NSTextField(wrappingLabelWithString: content.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        let host = NSTextField(labelWithString: content.host)
        host.font = .systemFont(ofSize: 11)
        host.textColor = .secondaryLabelColor
        host.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, host])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        let textWidth = max(Self.width(of: content.title, font: title.font), Self.width(of: content.host, font: host.font))
        let width = min(textWidth, 240) + 20
        title.preferredMaxLayoutWidth = width - 20
        let size = NSSize(width: width, height: stack.fittingSize.height)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityElement(false)
        let rowInScreen = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let x = opensTowardsLeft ? rowInScreen.minX - 8 - size.width : rowInScreen.maxX + 8
        panel.setFrameOrigin(NSPoint(x: x, y: rowInScreen.midY - size.height / 2))
        window.addChildWindow(panel, ordered: .above)
        self.panel = panel
    }
}
