import AppKit
import BatoCore

/// Arc's "Create a Space" page: it replaces the sidebar list while the new Space is named, themed and given an
/// icon. The theme previews on the whole window as it changes; nothing is saved until Create.
@MainActor
final class CreateSpacePageView: NSView, NSTextFieldDelegate {
    var onThemeChange: ((SpaceTheme) -> Void)?
    enum ProfileChoice: Equatable {
        case existing(UUID)
        case new(name: String, color: String)
    }

    var onCreate: ((String, String?, SpaceTheme, ProfileChoice) -> Void)?
    var onNewProfile: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var theme: SpaceTheme
    private var icon: String?
    private let profiles: [(id: UUID, name: String)]
    private var choice: ProfileChoice
    private let profilePill = NSButton()
    private let nameField = NSTextField()
    private let iconButton = NSButton()
    private let themeRow = PageRow()
    private let createButton = NSButton()
    private var themePopover: SpaceThemePopover?
    private var iconPopover: NSPopover?

    init(theme: SpaceTheme, profiles: [(id: UUID, name: String)], selected: UUID) {
        self.theme = theme
        self.profiles = profiles
        choice = .existing(selected)
        super.init(frame: .zero)
        setAccessibilityIdentifier("bato-create-space")
        build()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    override var isFlipped: Bool { true }

    func focusName() { window?.makeFirstResponder(nameField) }

    // MARK: Layout

    private func build() {
        let illustration = SpaceIllustration()
        let title = Self.label("Create a Space", size: 17, weight: .semibold, color: .labelColor)
        let subtitle = Self.label("Separate your tabs for life, work, projects, and more.", size: 13, weight: .regular,
                                  color: NSColor.labelColor.withAlphaComponent(0.85))
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 190

        let nameRow = PageRow()
        iconButton.isBordered = false
        iconButton.imagePosition = .imageOnly
        iconButton.target = self
        iconButton.action = #selector(chooseIcon)
        iconButton.setAccessibilityLabel("Space icon")
        iconButton.setAccessibilityIdentifier("bato-create-space-icon")
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.font = .systemFont(ofSize: 14, weight: .medium)
        nameField.placeholderString = "Space name…"
        nameField.delegate = self
        nameField.setAccessibilityLabel("Space name")
        nameField.setAccessibilityIdentifier("bato-create-space-name")
        nameRow.addSubview(iconButton)
        nameRow.addSubview(nameField)

        let profileRow = PageRow()
        let profileIcon = NSImageView(image: Self.symbol("person.crop.circle", 13))
        profileIcon.contentTintColor = NSColor.labelColor.withAlphaComponent(0.7)
        let profileLabel = Self.label("Profile", size: 13, weight: .semibold, color: .labelColor)
        profilePill.target = self
        profilePill.action = #selector(showProfileMenu(_:))
        profilePill.isBordered = false
        profilePill.font = .systemFont(ofSize: 11, weight: .semibold)
        profilePill.wantsLayer = true
        profilePill.layer?.cornerRadius = 10
        profilePill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        profilePill.setAccessibilityIdentifier("bato-create-space-profile")
        let info = NSButton(image: Self.symbol("info.circle", 13), target: nil, action: nil)
        info.isBordered = false
        info.contentTintColor = NSColor.labelColor.withAlphaComponent(0.6)
        info.toolTip = "Profiles keep logins and cookies separate. Spaces in the same Profile share them."
        info.setAccessibilityLabel("About Profiles")
        for view in [profileIcon, profileLabel, profilePill, info] { profileRow.addSubview(view) }

        let themeIcon = NSImageView(image: Self.symbol("paintbrush.pointed.fill", 12))
        themeIcon.contentTintColor = NSColor.labelColor.withAlphaComponent(0.7)
        let themeLabel = Self.label("Choose a Theme", size: 13, weight: .semibold, color: .labelColor)
        themeRow.onClick = { [weak self] in self?.toggleThemePopover() }
        themeRow.setAccessibilityLabel("Choose a Theme")
        themeRow.setAccessibilityIdentifier("bato-create-space-theme")
        themeRow.setAccessibilityRole(.button)
        themeRow.addSubview(themeIcon)
        themeRow.addSubview(themeLabel)

        createButton.title = "Create Space"
        createButton.font = .systemFont(ofSize: 13, weight: .semibold)
        createButton.isBordered = false
        createButton.wantsLayer = true
        createButton.layer?.cornerRadius = 8
        createButton.target = self
        createButton.action = #selector(create)
        createButton.setAccessibilityIdentifier("bato-create-space-create")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.isBordered = false
        cancel.font = .systemFont(ofSize: 13, weight: .medium)
        cancel.contentTintColor = NSColor.labelColor.withAlphaComponent(0.8)
        cancel.setAccessibilityIdentifier("bato-create-space-cancel")

        let all: [NSView] = [illustration, title, subtitle, nameRow, profileRow, themeRow, createButton, cancel]
        for view in all {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for view in [iconButton, nameField, profileIcon, profileLabel, profilePill, info, themeIcon, themeLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        let inset: CGFloat = 14
        func row(_ view: NSView, top: CGFloat, height: CGFloat) -> [NSLayoutConstraint] {
            [view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
             view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
             view.topAnchor.constraint(equalTo: topAnchor, constant: top),
             view.heightAnchor.constraint(equalToConstant: height)]
        }
        NSLayoutConstraint.activate(row(nameRow, top: 192, height: 35) + row(profileRow, top: 233, height: 37)
            + row(themeRow, top: 277, height: 37) + [
            illustration.centerXAnchor.constraint(equalTo: centerXAnchor),
            illustration.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            illustration.widthAnchor.constraint(equalToConstant: 70),
            illustration.heightAnchor.constraint(equalToConstant: 50),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 94),
            subtitle.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: topAnchor, constant: 122),
            subtitle.widthAnchor.constraint(equalToConstant: 190),
            iconButton.leadingAnchor.constraint(equalTo: nameRow.leadingAnchor, constant: 8),
            iconButton.centerYAnchor.constraint(equalTo: nameRow.centerYAnchor),
            iconButton.widthAnchor.constraint(equalToConstant: 22),
            iconButton.heightAnchor.constraint(equalToConstant: 22),
            nameField.leadingAnchor.constraint(equalTo: nameRow.leadingAnchor, constant: 34),
            nameField.trailingAnchor.constraint(equalTo: nameRow.trailingAnchor, constant: -8),
            nameField.centerYAnchor.constraint(equalTo: nameRow.centerYAnchor),
            profileIcon.leadingAnchor.constraint(equalTo: profileRow.leadingAnchor, constant: 11),
            profileIcon.centerYAnchor.constraint(equalTo: profileRow.centerYAnchor),
            profileLabel.leadingAnchor.constraint(equalTo: profileRow.leadingAnchor, constant: 32),
            profileLabel.centerYAnchor.constraint(equalTo: profileRow.centerYAnchor),
            profilePill.leadingAnchor.constraint(equalTo: profileLabel.trailingAnchor, constant: 8),
            profilePill.centerYAnchor.constraint(equalTo: profileRow.centerYAnchor),
            profilePill.heightAnchor.constraint(equalToConstant: 20),
            info.trailingAnchor.constraint(equalTo: profileRow.trailingAnchor, constant: -8),
            info.centerYAnchor.constraint(equalTo: profileRow.centerYAnchor),
            themeIcon.leadingAnchor.constraint(equalTo: themeRow.leadingAnchor, constant: 11),
            themeIcon.centerYAnchor.constraint(equalTo: themeRow.centerYAnchor),
            themeLabel.leadingAnchor.constraint(equalTo: themeRow.leadingAnchor, constant: 32),
            themeLabel.centerYAnchor.constraint(equalTo: themeRow.centerYAnchor),
            cancel.centerXAnchor.constraint(equalTo: centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            createButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            createButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            createButton.heightAnchor.constraint(equalToConstant: 36),
            createButton.bottomAnchor.constraint(equalTo: cancel.topAnchor, constant: -8)
        ])
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .center
        field.isSelectable = false
        return field
    }

    private static func symbol(_ name: String, _ size: CGFloat) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) ?? NSImage()
    }

    // MARK: State

    private var trimmedName: String { nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    func controlTextDidChange(_ obj: Notification) { refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): create(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelTapped(); return true
        default: return false
        }
    }

    func apply(theme: SpaceTheme) {
        self.theme = theme
        refresh()
    }

    private func refresh() {
        let enabled = !trimmedName.isEmpty
        createButton.isEnabled = enabled
        createButton.layer?.backgroundColor = (theme.primaryNSColor.blended(withFraction: 0.5, of: .black) ?? .systemIndigo)
            .withAlphaComponent(enabled ? 1 : 0.45).cgColor
        createButton.contentTintColor = .white
        createButton.attributedTitle = NSAttributedString(string: "Create Space", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(enabled ? 1 : 0.6)])
        profilePill.title = "\(profileName) ⌄"
        themeRow.highlighted = themePopover?.isShown ?? false
        if let icon {
            iconButton.image = Self.iconImage(icon, size: 16)
            iconButton.contentTintColor = .labelColor
        } else {
            iconButton.image = Self.placeholderIcon
            iconButton.contentTintColor = NSColor.labelColor.withAlphaComponent(0.55)
        }
    }

    static func iconImage(_ icon: String, size: CGFloat) -> NSImage? {
        if icon.hasPrefix("symbol:") {
            return NSImage(systemSymbolName: String(icon.dropFirst(7)), accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        }
        let font = NSFont.systemFont(ofSize: size)
        let text = NSAttributedString(string: icon, attributes: [.font: font])
        let bounds = text.size()
        return NSImage(size: bounds, flipped: false) { _ in text.draw(at: .zero); return true }
    }

    private static let placeholderIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        let box = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
        box.setLineDash([2, 2], count: 2, phase: 0)
        box.lineWidth = 1
        NSColor.black.setStroke()
        box.stroke()
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: 9, y: 5)); plus.line(to: NSPoint(x: 9, y: 13))
        plus.move(to: NSPoint(x: 5, y: 9)); plus.line(to: NSPoint(x: 13, y: 9))
        plus.lineWidth = 1.2
        plus.stroke()
        return true
        }
        image.isTemplate = true
        return image
    }()

    // MARK: Actions

    @objc private func create() {
        guard !trimmedName.isEmpty else { return }
        themePopover?.close()
        onCreate?(trimmedName, icon, theme, choice)
    }

    @objc private func cancelTapped() {
        themePopover?.close()
        onCancel?()
    }

    @objc private func showProfileMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(pickProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = choice == .existing(profile.id) ? .on : .off
            menu.addItem(item)
        }
        if case .new(let name, _) = choice {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.state = .on
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let create = NSMenuItem(title: "New Profile…", action: #selector(newProfile), keyEquivalent: "")
        create.target = self
        menu.addItem(create)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func pickProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        choice = .existing(id)
        refresh()
    }

    @objc private func newProfile() { onNewProfile?() }

    func chooseNewProfile(name: String, color: String) {
        choice = .new(name: name, color: color)
        refresh()
    }

    private var profileName: String {
        switch choice {
        case .existing(let id): return profiles.first { $0.id == id }?.name ?? "Default"
        case .new(let name, _): return name
        }
    }

    @objc private func chooseIcon() {
        if let iconPopover, iconPopover.isShown { return iconPopover.performClose(nil) }
        let picker = SpaceIconPicker { [weak self] choice in
            self?.icon = choice
            self?.iconPopover?.performClose(nil)
            self?.refresh()
            self?.focusName()
        }
        let controller = NSViewController()
        controller.view = picker
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = SpaceIconPicker.size
        popover.behavior = .transient
        popover.appearance = theme.appearance
        popover.show(relativeTo: iconButton.bounds, of: iconButton, preferredEdge: .maxY)
        iconPopover = popover
    }

    private func toggleThemePopover() {
        if let themePopover, themePopover.isShown { return themePopover.close() }
        let popover = SpaceThemePopover(theme: theme, onChange: { [weak self] in
            self?.theme = $0
            self?.onThemeChange?($0)
            self?.refresh()
        }, onClose: { [weak self] _ in
            self?.themePopover = nil
            self?.refresh()
        })
        themePopover = popover
        popover.show(relativeTo: themeRow.bounds, of: themeRow, preferredEdge: .maxX)
        refresh()
    }
}

/// A translucent rounded row; `highlighted` marks the one whose popover is open.
@MainActor
private final class PageRow: NSView {
    var highlighted = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(highlighted ? 0.18 : 0.09).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

/// Three fanned cards standing in for Arc's artwork.
@MainActor
private final class SpaceIllustration: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let centre = NSPoint(x: bounds.midX, y: bounds.midY + 2)
        for (angle, offset, tint) in [(-9.0, -17.0, NSColor.systemGreen), (9.0, 17.0, NSColor.systemRed), (0.0, 0.0, NSColor.systemGray)] {
            NSGraphicsContext.saveGraphicsState()
            var transform = AffineTransform(translationByX: centre.x + offset, byY: centre.y)
            transform.rotate(byDegrees: angle)
            let card = NSBezierPath(roundedRect: NSRect(x: -16, y: -20, width: 32, height: 40), xRadius: 3, yRadius: 3)
            card.transform(using: transform)
            NSColor.white.setFill()
            card.fill()
            let mark = NSBezierPath(roundedRect: NSRect(x: -10, y: -14, width: 20, height: 14), xRadius: 2, yRadius: 2)
            mark.transform(using: transform)
            tint.withAlphaComponent(0.55).setFill()
            mark.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// Emoji and SF Symbol grids behind two tabs.
@MainActor
final class SpaceIconPicker: NSView {
    static let size = NSSize(width: 272, height: 270)
    private static let emoji = Array("😀😃😄😁😆😅🤣😂🙂🙃😉😊😇🥰😍🤩😘😋😛😜🤪😎🤓🧐🤠🥳😴🤯😱🤔🫡🤗🌞🌙⭐🔥🌈🌱🌳🌸🍀🍎🍕🍔☕🍺🎵🎮🎬📚💻📱💡🔧🛠🎨✈🚗🏠🏢💼🎁❤💜💙💚🏁🚀🧪🧠🐱🐶🦊🐼🐸🦄🐝").map(String.init)
    private static let symbols = ["star.fill", "bookmark.fill", "heart.fill", "flag.fill", "bolt.fill", "triangle.fill", "asterisk", "bell.fill",
                                  "lightbulb.fill", "drop.fill", "square.grid.2x2.fill", "circle.grid.3x3.fill", "square.stack.3d.up.fill",
                                  "externaldrive.fill", "tray.fill", "doc.on.doc.fill", "folder.fill", "archivebox.fill", "calendar",
                                  "envelope.fill", "checkmark.square.fill", "doc.fill", "book.fill", "bubble.left.fill", "person.2.fill",
                                  "terminal.fill", "hammer.fill", "square.fill", "leaf.fill", "circle.fill", "moon.fill", "sun.max.fill",
                                  "globe", "cloud.fill", "pawprint.fill", "gift.fill", "bed.double.fill", "fork.knife", "dumbbell.fill",
                                  "airplane", "music.note", "paintpalette.fill", "video.fill", "pills.fill", "chevron.left.forwardslash.chevron.right",
                                  "basketball.fill", "map.fill", "graduationcap.fill", "cart.fill", "house.fill", "briefcase.fill", "gamecontroller.fill"]
    private let onPick: (String) -> Void
    private let content = NSView()
    private let tabs = NSSegmentedControl(labels: ["Emoji", "Icon"], trackingMode: .selectOne, target: nil, action: nil)

    init(onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.frame = NSRect(x: 76, y: 232, width: 120, height: 24)
        addSubview(tabs)
        content.frame = NSRect(x: 8, y: 8, width: 256, height: 216)
        addSubview(content)
        show(emoji: true)
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    @objc private func tabChanged() { show(emoji: tabs.selectedSegment == 0) }

    private func show(emoji: Bool) {
        content.subviews.forEach { $0.removeFromSuperview() }
        let columns = emoji ? 7 : 8
        let items = emoji ? Self.emoji : Self.symbols
        let pitch: CGFloat = emoji ? 35 : 32
        let rows = (items.count + columns - 1) / columns
        let grid = NSView(frame: NSRect(x: 0, y: 0, width: 256, height: max(216, CGFloat(rows) * pitch)))
        for (index, item) in items.enumerated() {
            let button = NSButton()
            button.isBordered = false
            button.imagePosition = .imageOnly
            let value = emoji ? item : "symbol:\(item)"
            button.image = CreateSpacePageView.iconImage(value, size: emoji ? 20 : 15)
            button.contentTintColor = .labelColor
            button.identifier = NSUserInterfaceItemIdentifier(value)
            button.target = self
            button.action = #selector(picked(_:))
            button.setAccessibilityLabel(item)
            button.frame = NSRect(x: CGFloat(index % columns) * pitch, y: grid.frame.height - CGFloat(index / columns + 1) * pitch,
                                  width: pitch, height: pitch)
            grid.addSubview(button)
        }
        let scroll = NSScrollView(frame: content.bounds)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = grid
        content.addSubview(scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: grid.frame.height - content.bounds.height))
    }

    @objc private func picked(_ sender: NSButton) {
        if let value = sender.identifier?.rawValue { onPick(value) }
    }
}
