import AppKit

/// One line of the workspace and Profile switcher.
enum SwitcherEntry {
    case header(title: String, dot: NSColor)
    case item(title: String, dot: NSColor?, symbol: String?, checked: Bool, shortcut: String?, enabled: Bool,
              identifier: String, action: () -> Void)
    case separator
}

/// The workspace and Profile switcher as a popover: it follows the appearance and Reduce Transparency
/// like any system popover, and every row is a pressable accessibility element. Replaces an NSMenu so
/// colour dots, check marks and the settings gear can be laid out as in Dia.
@MainActor
final class SwitcherPopover: NSObject, NSPopoverDelegate {
    static let width: CGFloat = 260
    private let popover = NSPopover()

    var isShown: Bool { popover.isShown }

    func show(_ entries: [SwitcherEntry], relativeTo anchor: NSView, edge: NSRectEdge = .maxY) {
        popover.close()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for entry in entries {
            let view = makeView(for: entry)
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
        }
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        let host = NSViewController()
        host.view = content
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }

    func close() { popover.close() }

    private func makeView(for entry: SwitcherEntry) -> NSView {
        switch entry {
        case .separator:
            let line = NSBox()
            line.boxType = .separator
            return line
        case .header(let title, let dot):
            return SwitcherRow(title: title, dot: dot, symbol: nil, checked: false, shortcut: nil, enabled: false,
                               isHeader: true, identifier: nil, action: nil)
        case .item(let title, let dot, let symbol, let checked, let shortcut, let enabled, let identifier, let action):
            return SwitcherRow(title: title, dot: dot, symbol: symbol, checked: checked, shortcut: shortcut,
                               enabled: enabled, isHeader: false, identifier: identifier) { [weak self] in
                self?.popover.close()
                DispatchQueue.main.async(execute: action)
            }
        }
    }
}

@MainActor
private final class SwitcherRow: NSView {
    private let action: (() -> Void)?
    private let enabled: Bool
    private var hovered = false { didSet { refreshFill() } }
    private var tracking: NSTrackingArea?

    init(title: String, dot: NSColor?, symbol: String?, checked: Bool, shortcut: String?, enabled: Bool,
         isHeader: Bool, identifier: String?, action: (() -> Void)?) {
        self.action = action
        self.enabled = enabled
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        let leading = NSImageView()
        leading.translatesAutoresizingMaskIntoConstraints = false
        if let symbol {
            leading.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            leading.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            leading.contentTintColor = .secondaryLabelColor
        } else if let dot {
            leading.image = SwitcherRow.dotImage(dot, large: !isHeader)
        }
        leading.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 14)
        label.textColor = isHeader || !enabled ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) ?? NSImage())
        check.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        check.contentTintColor = .labelColor
        check.isHidden = !checked
        check.widthAnchor.constraint(equalToConstant: 14).isActive = true
        var views: [NSView] = [leading, label]
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        views.append(spacer)
        if let shortcut {
            let keys = NSTextField(labelWithString: shortcut)
            keys.font = .systemFont(ofSize: 13)
            keys.textColor = .secondaryLabelColor
            views.append(keys)
        }
        views.append(check)
        let row = NSStackView(views: views)
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: isHeader ? 24 : 27),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if action != nil {
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel(title)
            setAccessibilityValue(checked ? "current" : nil)
            setAccessibilityEnabled(enabled)
            if let identifier { setAccessibilityIdentifier(identifier) }
        }
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    private static func dotImage(_ color: NSColor, large: Bool) -> NSImage {
        let size: CGFloat = large ? 10 : 8
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: (rect.width - size) / 2, y: (rect.height - size) / 2, width: size, height: size)).fill()
            return true
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard enabled, let action else { return false }
        action()
        return true
    }

    override func mouseDown(with event: NSEvent) { if enabled { action?() } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidChangeEffectiveAppearance() { refreshFill() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard action != nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = enabled }
    override func mouseExited(with event: NSEvent) { hovered = false }

    private func refreshFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = hovered ? SidebarStyle.rowFill(selected: false, hovered: true, tile: false)?.cgColor : nil
        }
    }
}
