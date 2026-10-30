import AppKit
import BatoCore
import BatoPersistence
import BatoRuntime

/// The native sidebar only. Chromium owns page views, origin UI and browser data.
/// The caller must wire the engine's event sink before calling `start()`.
@MainActor
public final class NativeWorkspaceController: NSObject, NSTextFieldDelegate {
    public let root: NSView
    public let runtime: PageRuntime
    public var requestNativeFocus: (() -> Void)?
    public var focusTarget: NSView { addressField }

    private let addressField = NSTextField(string: "")
    private let entries = SidebarEntries()
    private let workspacePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let profileLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var workspaceIDs: [UUID] = []
    private var hasStarted = false
    private let accent = NSColor(srgbRed: 0.66, green: 0.40, blue: 0.43, alpha: 1)

    /// Load failures throw without replacing the existing document. The factory
    /// receives the organization Profile to bind to an explicit engine context.
    /// It must not infer engine isolation from this UUID alone.
    public init(directory: URL, makeEngine: (UUID) throws -> any PageEngine) throws {
        let store = OrganizationStore<BrowserState>(directory: directory, validate: { try $0.validate() })
        let state: BrowserState
        if let restored = try store.load() {
            state = restored
        } else {
            state = BrowserState.initial()
            try store.save(state)
        }
        let engine = try makeEngine(state.currentWorkspace.profileID)
        runtime = try PageRuntime(state: state, engine: engine, commit: { try store.save($0) })
        root = WorkspaceRoot(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        super.init()
        configureView()
        runtime.onStateChange = { [weak self] _ in self?.render() }
        render()
    }

    /// Call only after attaching the root and wiring the engine callback sink.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        _ = runtime.start()
        render()
    }

    public func receive(_ event: PageEvent) {
        runtime.receive(event)
        render()
    }

    /// Focuses native address entry. Host menu commands may call this method.
    public func newTab() {
        requestNativeFocus?()
        root.window?.makeFirstResponder(addressField)
        addressField.selectText(nil)
    }

    public func closeSelection() {
        guard let id = runtime.state.currentWorkspace.activeEntryID else { return }
        perform { runtime.closeEntry(id) }
    }

    private func configureView() {
        root.wantsLayer = true
        root.layer?.backgroundColor = accent.withAlphaComponent(0.09).cgColor
        root.setAccessibilityIdentifier("bato-workspace-sidebar")
        if let view = root as? WorkspaceRoot {
            view.newTab = { [weak self] in self?.newTab() }
            view.closeSelection = { [weak self] in self?.closeSelection() }
        }

        let title = NSTextField(labelWithString: "bato")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let build = NSTextField(labelWithString: "Development build")
        build.font = .systemFont(ofSize: 10)
        build.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, build])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 2

        addressField.placeholderString = "Website address"
        addressField.setAccessibilityLabel("New tab address")
        addressField.setAccessibilityIdentifier("bato-new-tab-address")
        addressField.delegate = self
        addressField.target = self
        addressField.action = #selector(submitAddress)
        // Return submits through the explicit action. Merely moving focus to a
        // page/tab must not resubmit the cleared address or show a false error.
        addressField.cell?.sendsActionOnEndEditing = false
        let add = ActionButton(title: "New tab") { [weak self] in self?.submitAddress() }
        add.setAccessibilityIdentifier("bato-new-tab")
        let address = NSStackView(views: [addressField, add])
        address.orientation = .vertical
        address.alignment = .leading
        address.spacing = 7
        addressField.widthAnchor.constraint(equalTo: address.widthAnchor).isActive = true

        entries.orientation = .vertical
        entries.alignment = .leading
        entries.spacing = 9
        entries.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = entries
        NSLayoutConstraint.activate([
            entries.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            entries.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            entries.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        workspacePicker.target = self
        workspacePicker.action = #selector(workspaceChanged)
        workspacePicker.setAccessibilityLabel("Workspace")
        workspacePicker.setAccessibilityIdentifier("bato-workspace-picker")
        workspacePicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let workspaceAdd = ActionButton(title: "+") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.addWorkspace(name: "Workspace \(self.runtime.state.workspaces.count + 1)") }
        }
        workspaceAdd.setAccessibilityLabel("New workspace")
        let workspaceRow = NSStackView(views: [workspacePicker, workspaceAdd])
        workspaceRow.orientation = .horizontal
        workspaceRow.spacing = 6
        workspacePicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        profileLabel.font = .systemFont(ofSize: 11)
        profileLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("bato-workspace-status")

        let stack = NSStackView(views: [heading, address, scroll, workspaceRow, profileLabel, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            address.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            workspaceRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func render() {
        let state = runtime.state
        let workspace = state.currentWorkspace
        for view in entries.arrangedSubviews {
            entries.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let favorites = state.profiles.first(where: { $0.id == workspace.profileID })?.favorites ?? []
        addSection("Favorites", pages: favorites)
        addSection("Pinned", pages: workspace.pins)
        addSection("Tabs", pages: workspace.tabs)
        workspaceIDs = state.workspaces.map(\.id)
        workspacePicker.removeAllItems()
        workspacePicker.addItems(withTitles: state.workspaces.map(\.name))
        if let index = workspaceIDs.firstIndex(of: state.activeWorkspaceID) { workspacePicker.selectItem(at: index) }
        profileLabel.stringValue = state.profiles.first(where: { $0.id == workspace.profileID })?.name ?? ""
        switch runtime.lastError {
        case .none:
            statusLabel.stringValue = runtime.pendingClose.isEmpty ? "" : "Waiting for page to close…"
        case .unsupportedProfile:
            statusLabel.stringValue = "This Profile isn’t connected to the browser yet."
        case .creationRejected:
            statusLabel.stringValue = "The page couldn’t open. Select it to try again."
        case .saveFailed:
            statusLabel.stringValue = "Changes couldn’t be saved. Reopen Bato to reload organization."
        case .invalidCommand:
            statusLabel.stringValue = "This action couldn’t be completed."
        }
    }

    private func addSection(_ title: String, pages: [PageEntry]) {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        entries.addArrangedSubview(label)
        if pages.isEmpty {
            let empty = NSTextField(labelWithString: title == "Tabs" ? "Your tabs appear here" : "No \(title.lowercased()) yet")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .tertiaryLabelColor
            entries.addArrangedSubview(empty)
        }
        for page in pages {
            let select = ActionButton(title: page.title.isEmpty ? (page.lastURL.host ?? "Page") : page.title) { [weak self] in
                guard let self else { return }
                self.perform { self.runtime.selectEntry(page.id) }
            }
            select.bezelStyle = .recessed
            select.alignment = .left
            select.setButtonType(.momentaryPushIn)
            select.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            select.setContentHuggingPriority(.defaultLow, for: .horizontal)
            (select.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            select.setAccessibilityIdentifier("bato-page-\(page.id.uuidString)")
            select.toolTip = page.lastURL.host
            if page.kind == .temporary {
                let menu = NSMenu()
                menu.addItem(ActionMenuItem(title: "Pin Tab") { [weak self] in
                    guard let self else { return }
                    self.perform { self.runtime.pinEntry(page.id) }
                })
                menu.addItem(ActionMenuItem(title: "Add to Favorites") { [weak self] in
                    guard let self else { return }
                    self.perform { self.runtime.favoriteEntry(page.id) }
                })
                select.menu = menu
            }
            let close = ActionButton(title: "×") { [weak self] in
                guard let self else { return }
                self.perform { self.runtime.closeEntry(page.id) }
            }
            close.setAccessibilityLabel(page.kind == .temporary ? "Close \(select.title)" : "Unload \(select.title)")
            close.toolTip = page.kind == .temporary ? "Close tab" : "Unload saved page"
            close.isEnabled = !runtime.pendingClose.contains(where: { $0.entryID == page.id })
            let row = NSStackView(views: [select, close])
            row.orientation = .horizontal
            row.spacing = 3
            row.wantsLayer = true
            row.layer?.cornerRadius = 7
            row.layer?.backgroundColor = runtime.state.currentWorkspace.activeEntryID == page.id
                ? accent.withAlphaComponent(0.17).cgColor : NSColor.clear.cgColor
            entries.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
            close.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
    }

    private func perform(_ command: () -> Bool) {
        guard hasStarted else { return }
        _ = command()
        render()
    }

    @objc private func submitAddress() {
        guard hasStarted else { return }
        let text = addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else {
            statusLabel.stringValue = "Enter a website address using HTTP or HTTPS."
            return
        }
        let before = runtime.state
        _ = runtime.addTab(url: url, title: url.host ?? "New tab")
        // Creation can fail after a successful organization commit. Clear only
        // when that commit added the entry; preserve text on a failed save.
        if runtime.state != before { addressField.stringValue = "" }
        render()
    }

    @objc private func workspaceChanged() {
        let index = workspacePicker.indexOfSelectedItem
        guard workspaceIDs.indices.contains(index) else { return }
        perform { runtime.activateWorkspace(workspaceIDs[index]) }
    }
}

@MainActor
private final class SidebarEntries: NSStackView {
    // NSClipView uses the document's coordinate direction when its height is
    // shorter than the viewport. Top-origin content stays below address entry
    // instead of being bottom-aligned above the workspace footer.
    override var isFlipped: Bool { true }
}

@MainActor
private final class WorkspaceRoot: NSView {
    var newTab: (() -> Void)?
    var closeSelection: (() -> Void)?
    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Bato workspace sidebar" }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard modifiers == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "t": newTab?(); return true
        case "w": closeSelection?(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

@MainActor
private final class ActionButton: NSButton {
    private let invoke: () -> Void
    init(title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(runAction)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    @objc private func runAction() { invoke() }
}

@MainActor
private final class ActionMenuItem: NSMenuItem {
    private let invoke: () -> Void
    init(title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(title: title, action: nil, keyEquivalent: "")
        target = self
        action = #selector(runAction)
    }
    required init(coder: NSCoder) { fatalError("Not supported") }
    @objc private func runAction() { invoke() }
}
