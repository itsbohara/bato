import AppKit
import BatoBlocking
import BatoCore

/// What the Settings window needs from the workspace. Every action runs against the current
/// organization at the moment it is invoked, never against a snapshot held by the window.
struct SettingsHooks {
    let state: () -> BrowserState
    let blockingService: (String) -> BlockingService?
    let createProfile: () -> Void
    let renameCurrentProfile: () -> Void
    let importFromArc: () -> Void
    let openEssential: (BrowserEssential) -> Void
    let defaultBrowser: DefaultBrowser
    let recovery: RecoveryController
    let setArchivePeriod: (ArchivePeriod) -> Void
    let setWorkspaceArchivePeriod: (UUID, ArchivePeriod?) -> Void
    let openArchive: () -> Void
}

extension DefaultBrowser {
    /// Bato as the running application, checked against what Launch Services hands web links to.
    static func system(appURL: URL = Bundle.main.bundleURL) -> DefaultBrowser {
        DefaultBrowser(appURL: appURL, handler: { scheme in
            URL(string: "\(scheme)://example.com").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        }, assign: { scheme in
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme)
        })
    }
}

/// Bato's own preferences, in a standalone window. Chromium's settings stay in their web page.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let hooks: SettingsHooks
    private let window: NSWindow
    private let sidebarStack = NSStackView()
    private let contentHost = NSView()
    private var sidebarButtons: [SettingsPane: SettingsSidebarButton] = [:]
    private(set) var pane: SettingsPane = .profiles

    init(hooks: SettingsHooks) {
        self.hooks = hooks
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("BatoSettings")
        buildLayout()
    }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { self.pane = pane }
        reload()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// Rebuilds the visible pane from current organization, e.g. after a Profile was created.
    func reload() {
        for (candidate, button) in sidebarButtons { button.isSelected = candidate == pane }
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        // Legacy scrollers take 16 pt from the clip view, narrowing cards on long panes only.
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let column = NSStackView(views: [heading(pane.title)] + content(for: pane))
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 20
        column.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)
        scroll.documentView = document
        contentHost.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentHost.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            column.topAnchor.constraint(equalTo: document.topAnchor, constant: 60),
            column.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 40),
            column.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -40),
            column.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
        ])
        for view in column.arrangedSubviews { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
    }

    // MARK: Layout

    private func buildLayout() {
        let rail = NSVisualEffectView()
        rail.material = .sidebar
        rail.blendingMode = .behindWindow
        rail.state = .followsWindowActiveState
        rail.translatesAutoresizingMaskIntoConstraints = false
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 4
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        for candidate in SettingsPane.allCases {
            let button = SettingsSidebarButton(title: candidate.title, symbol: candidate.symbolName) { [weak self] in
                self?.pane = candidate
                self?.reload()
            }
            sidebarButtons[candidate] = button
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        }
        rail.addSubview(sidebarStack)
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(rail)
        root.addSubview(contentHost)
        window.contentView = root
        NSLayoutConstraint.activate([
            rail.topAnchor.constraint(equalTo: root.topAnchor),
            rail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            rail.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rail.widthAnchor.constraint(equalToConstant: 270),
            sidebarStack.topAnchor.constraint(equalTo: rail.topAnchor, constant: 60),
            sidebarStack.leadingAnchor.constraint(equalTo: rail.leadingAnchor, constant: 14),
            sidebarStack.trailingAnchor.constraint(equalTo: rail.trailingAnchor, constant: -14),
            contentHost.topAnchor.constraint(equalTo: root.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentHost.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
    }

    private func content(for pane: SettingsPane) -> [NSView] {
        switch pane {
        case .profiles: profilesPane()
        case .privacy: privacyPane()
        case .archive: archivePane()
        case .importData: importPane()
        case .shortcuts: shortcutsPane()
        case .advanced: advancedPane()
        }
    }

    // MARK: Panes

    private func profilesPane() -> [NSView] {
        let note = caption("Each Profile keeps its own history, downloads, logins, cookies and extensions.")
        let rows = SettingsProfileRow.rows(from: hooks.state()).map { row -> NSView in
            let action: NSView? = row.isCurrent ? SettingsPillButton(title: "Rename…") { [weak self] in
                self?.hooks.renameCurrentProfile()
            } : nil
            return SettingsRow(leading: ColorDot(hex: row.colorHex), title: row.name, detail: row.detail, trailing: action)
        }
        let create = SettingsPillButton(title: "Create Profile…") { [weak self] in self?.hooks.createProfile() }
        return [note, SettingsGroup(rows: rows), trailingAligned(create)]
    }

    private func privacyPane() -> [NSView] {
        let state = hooks.state()
        guard let profile = state.profiles.first(where: { $0.id == state.currentWorkspace.profileID }),
              let service = hooks.blockingService(profile.id.uuidString) else {
            return [caption("Content blocking starts with the browser engine and isn’t available yet."),
                    caption("Site permissions"), sitePermissionsGroup(detail: "Camera, location, notifications and more, per site.")]
        }
        let toggle = NSSwitch()
        toggle.state = service.settings.enabled ? .on : .off
        let handler = ActionTarget { [weak self, weak toggle] in
            guard let toggle else { return }
            if (try? service.setEnabled(toggle.state == .on)) == nil { toggle.state = toggle.state == .on ? .off : .on }
            self?.reload()
        }
        toggle.target = handler
        toggle.action = #selector(ActionTarget.fire)
        toggle.setAccessibilityLabel("Block ads and trackers")
        let blocking = SettingsRow(leading: SymbolTile(symbol: "hand.raised.fill", color: .systemRed),
                                   title: "Block ads and trackers", detail: "For the \(profile.name) Profile",
                                   trailing: toggle, keeping: handler)
        var views: [NSView] = [caption("Content blocking"), SettingsGroup(rows: [blocking, uBlockListsRow()])]
        views += sitePermissions(forProfile: profile.name)
        let exceptions = service.exceptions
        views.append(caption(exceptions.isEmpty ? "No sites are excluded from blocking." : "Sites excluded from blocking"))
        if !exceptions.isEmpty {
            views.append(SettingsGroup(rows: exceptions.map { host in
                SettingsRow(leading: nil, title: host, detail: nil, trailing: SettingsPillButton(title: "Remove") { [weak self] in
                    try? service.removeException(host: host)
                    self?.reload()
                })
            }))
        }
        return views
    }

    private func uBlockListsRow() -> NSView {
        let tile = SymbolTile(symbol: "shield.lefthalf.filled", color: .systemOrange)
        let title = "uBlock Origin filter lists"
        guard let blocking = BlockingHost.shared.profiles else {
            return SettingsRow(leading: tile, title: title, detail: "Available once content blocking has started.", trailing: nil)
        }
        if blocking.uBlockChoice == .enabled {
            return SettingsRow(leading: tile, title: title,
                               detail: "Added for every Profile and updated daily.",
                               trailing: SettingsPillButton(title: "Remove") { [weak self] in
                                   UBlockOffer.remove(blocking: blocking) { self?.reload() }
                               })
        }
        return SettingsRow(leading: tile, title: title,
                           detail: "More filters from the uBlock Origin project. Downloaded only if you add them.",
                           trailing: SettingsPillButton(title: "Add…") { [weak self] in
                               guard let self else { return }
                               UBlockOffer.present(on: window, blocking: blocking) { [weak self] in self?.reload() }
                           })
    }

    private func archivePane() -> [NSView] {
        let state = hooks.state()
        let global = SettingsRow(leading: SymbolTile(symbol: "archivebox.fill", color: .systemIndigo),
                                 title: "Archive tabs", detail: "Temporary tabs you haven’t used move to the Archive. Pins and Favorites stay.",
                                 trailing: ArchivePeriodPicker(selected: state.archive.period, includeDefault: false) { [weak self] in
                                     self?.hooks.setArchivePeriod($0 ?? .never)
                                     self?.reload()
                                 })
        var views: [NSView] = [SettingsGroup(rows: [global])]
        let profileID = state.currentWorkspace.profileID
        let rows = state.workspaces.filter { $0.profileID == profileID }.map { workspace in
            SettingsRow(leading: ColorDot(hex: workspace.color), title: workspace.name,
                        detail: workspace.archivePeriod == nil ? "Uses the setting above" : nil,
                        trailing: ArchivePeriodPicker(selected: workspace.archivePeriod, includeDefault: true) { [weak self] in
                            self?.hooks.setWorkspaceArchivePeriod(workspace.id, $0)
                            self?.reload()
                        })
        }
        if rows.count > 1 { views += [caption("Workspaces"), SettingsGroup(rows: rows)] }
        let count = state.archive.records(inProfile: profileID).count
        let open = SettingsRow(leading: nil, title: "Archived tabs",
                               detail: count == 0 ? "Nothing is archived yet." : "\(count) archived in this Profile.",
                               trailing: SettingsPillButton(title: "Open Archive…") { [weak self] in self?.hooks.openArchive() })
        return views + [caption("Restore"), SettingsGroup(rows: [open])]
    }

    private func sitePermissions(forProfile name: String) -> [NSView] {
        [caption("Site permissions"),
         sitePermissionsGroup(detail: "Camera, location, notifications and more, per site, for the \(name) Profile.")]
    }

    private func sitePermissionsGroup(detail: String) -> NSView {
        SettingsGroup(rows: [SettingsRow(leading: SymbolTile(symbol: "checkmark.shield.fill", color: .systemBlue),
                                         title: "Site permissions", detail: detail,
                                         trailing: SettingsPillButton(title: "Manage…") { [weak self] in
                                             self?.hooks.openEssential(.sitePermissions)
                                         })])
    }

    private func importPane() -> [NSView] {
        let button = SettingsPillButton(title: "Import from Arc…") { [weak self] in self?.hooks.importFromArc() }
        let row = SettingsRow(leading: SymbolTile(symbol: "square.and.arrow.down.fill", color: .systemBlue),
                              title: "Arc", detail: "Pins, tabs and Spaces. You choose the file and preview the result first.",
                              trailing: button)
        return [caption("Bring your organization from another browser. Nothing in the other browser is changed."),
                SettingsGroup(rows: [row])]
    }

    private func shortcutsPane() -> [NSView] {
        [SettingsGroup(rows: ShortcutCatalog.rows.map { shortcut in
            SettingsRow(leading: nil, title: shortcut.title, detail: nil, trailing: keyLabel(shortcut.keys))
        })]
    }

    private func defaultBrowserRow() -> NSView {
        let browser = hooks.defaultBrowser
        if browser.status == .isDefault {
            return SettingsRow(leading: nil, title: "Default browser", detail: "Bato opens links from other apps.",
                               trailing: nil)
        }
        return SettingsRow(leading: nil, title: "Default browser",
                           detail: "Bato isn’t your default browser. macOS asks you to confirm the change.",
                           trailing: SettingsPillButton(title: "Make Bato Default") { [weak self] in
                               Task { @MainActor in
                                   try? await browser.makeDefault()
                                   self?.reload()
                               }
                           })
    }

    private func advancedPane() -> [NSView] {
        let pages: [(BrowserEssential, String)] = [
            (.history, "Browsing history for the current Profile."),
            (.downloads, "Files downloaded in the current Profile."),
            (.chromiumSettings, "Chromium’s own settings: search engine, passwords, site permissions and more."),
        ]
        let rows = pages.map { essential, detail in
            SettingsRow(leading: nil, title: essential.title, detail: detail,
                        trailing: SettingsPillButton(title: "Open") { [weak self] in self?.hooks.openEssential(essential) })
        }
        let backup = SettingsRow(leading: nil, title: "Backups",
                                 detail: "Restore your organization and blocking settings from a daily or pre-import copy.",
                                 trailing: SettingsPillButton(title: "Restore from backup…") { [weak self] in
                                     guard let self else { return }
                                     hooks.recovery.presentRestorePicker(on: window) { [weak self] in self?.reload() }
                                 })
        var backupRows = [backup]
        if let staged = hooks.recovery.stagedRestoreTitle {
            backupRows.append(SettingsRow(leading: nil, title: "Restore staged",
                                          detail: "“\(staged)” will replace your organization the next time Bato opens.",
                                          trailing: SettingsPillButton(title: "Cancel staged restore") { [weak self] in
                                              self?.hooks.recovery.cancelStagedRestore()
                                              self?.reload()
                                          }))
        }
        return [caption("General"), SettingsGroup(rows: [defaultBrowserRow()]),
                caption("Browser pages"), SettingsGroup(rows: rows), caption("Backup"), SettingsGroup(rows: backupRows)]
    }

    // MARK: Pieces

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func keyLabel(_ keys: String) -> NSTextField {
        let label = NSTextField(labelWithString: keys)
        label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func trailingAligned(_ view: NSView) -> NSView {
        let container = NSStackView(views: [NSView(), view])
        container.orientation = .horizontal
        return container
    }
}

// MARK: - Views

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class ActionTarget: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

private final class SettingsSidebarButton: NSControl {
    private let handler: () -> Void
    var isSelected = false { didSet { updateAppearance() } }
    private let label: NSTextField
    private let icon: NSImageView

    init(title: String, symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        label = NSTextField(labelWithString: title)
        icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        label.font = .systemFont(ofSize: 17, weight: .medium)
        icon.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            icon.widthAnchor.constraint(equalToConstant: 26),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        updateAppearance()
    }

    /// The rail must work on the first click even while another window is key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { handler(); return true }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func mouseDown(with event: NSEvent) { handler() }
    override func viewDidChangeEffectiveAppearance() { updateAppearance() }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
        }
        let color: NSColor = isSelected ? .white : .labelColor
        label.textColor = color
        icon.contentTintColor = color
        setAccessibilityValue(isSelected ? "selected" : nil)
    }
}

private final class SettingsGroup: NSView {
    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = NSBox()
                line.boxType = .separator
                stack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidChangeEffectiveAppearance() { updateColors() }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
    }
}

private final class SettingsRow: NSView {
    private let keepAlive: AnyObject?

    init(leading: NSView?, title: String, detail: String?, trailing: NSView?, keeping: AnyObject? = nil) {
        keepAlive = keeping
        super.init(frame: .zero)
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 17)
        name.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [name])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        if let detail {
            let sub = NSTextField(wrappingLabelWithString: detail)
            sub.font = .systemFont(ofSize: 14)
            sub.textColor = .secondaryLabelColor
            text.addArrangedSubview(sub)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing?.setContentHuggingPriority(.required, for: .horizontal)
        trailing?.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [leading, text, trailing].compactMap { $0 })
        row.spacing = 14
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
}

private final class SettingsPillButton: NSButton {
    private let handlerTarget: ActionTarget

    init(title: String, handler: @escaping () -> Void) {
        handlerTarget = ActionTarget(handler)
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .large
        font = .systemFont(ofSize: 15)
        target = handlerTarget
        action = #selector(ActionTarget.fire)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
}

private final class ArchivePeriodPicker: NSPopUpButton {
    private let handler: ActionTarget

    /// `nil` stands for "follow the global setting" when `includeDefault` is set.
    init(selected: ArchivePeriod?, includeDefault: Bool, choose: @escaping (ArchivePeriod?) -> Void) {
        let periods: [ArchivePeriod?] = (includeDefault ? [nil] : []) + ArchivePeriod.allCases.map { Optional($0) }
        var picker: (() -> Int)?
        handler = ActionTarget { choose(periods[picker?() ?? 0]) }
        super.init(frame: .zero, pullsDown: false)
        picker = { [unowned self] in indexOfSelectedItem }
        addItems(withTitles: periods.map { $0?.title ?? "Use default" })
        selectItem(at: periods.firstIndex(of: selected) ?? 0)
        controlSize = .large
        target = handler
        action = #selector(ActionTarget.fire)
        setAccessibilityLabel("Archive period")
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
}

private final class ColorDot: NSView {
    init(hex: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor(hexString: hex).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 18).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
}

private final class SymbolTile: NSView {
    init(symbol: String, color: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = color.cgColor
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .white
        image.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36), heightAnchor.constraint(equalToConstant: 36),
            image.centerXAnchor.constraint(equalTo: centerXAnchor), image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
}

private extension NSColor {
    convenience init(hexString: String) {
        let digits = hexString.dropFirst()
        let value = UInt32(digits, radix: 16) ?? 0xB47879
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
