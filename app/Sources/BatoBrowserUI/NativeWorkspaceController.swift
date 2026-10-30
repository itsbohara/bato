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
    private let workspaceActions = NSButton(frame: .zero)
    private let profileLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var workspaceIDs: [UUID] = []
    private var hasStarted = false
    private var workspaceEditor: WorkspaceEditor?
    private var accent: NSColor { workspaceColor(runtime.state.currentWorkspace.color) }

    /// Load failures throw without replacing the existing document. The factory
    /// receives the organization Profile to bind to an explicit engine context.
    /// It must not infer engine isolation from this UUID alone.
    /// Hosts with their own scoped keyboard router must disable sidebar key equivalents.
    public init(directory: URL, handlesKeyEquivalents: Bool = true,
                makeEngine: (UUID) throws -> any PageEngine) throws {
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
        let sidebar = WorkspaceRoot(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        sidebar.keyEquivalentsEnabled = handlesKeyEquivalents
        root = sidebar
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
        let workspaceEdit = ActionButton(title: "Edit…") { [weak self] in self?.editWorkspace() }
        workspaceEdit.setAccessibilityLabel("Edit workspace")
        workspaceEdit.setAccessibilityIdentifier("bato-edit-workspace")
        workspaceEdit.toolTip = "Edit workspace name and color"
        workspaceActions.title = "…"
        workspaceActions.bezelStyle = .rounded
        workspaceActions.target = self
        workspaceActions.action = #selector(showWorkspaceActions)
        workspaceActions.setAccessibilityLabel("Workspace actions")
        workspaceActions.setAccessibilityIdentifier("bato-workspace-actions")
        workspaceActions.toolTip = "Reorder this workspace"
        let workspaceActionRow = NSStackView(views: [workspaceEdit, workspaceActions])
        workspaceActionRow.orientation = .horizontal
        workspaceActionRow.spacing = 6
        let workspaceRow = NSStackView(views: [workspacePicker, workspaceAdd])
        let workspaceControls = NSStackView(views: [workspaceRow, workspaceActionRow])
        workspaceControls.orientation = .vertical
        workspaceControls.alignment = .leading
        workspaceControls.spacing = 5
        workspaceRow.orientation = .horizontal
        workspaceRow.spacing = 6
        workspacePicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        profileLabel.font = .systemFont(ofSize: 11)
        profileLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("bato-workspace-status")

        let stack = NSStackView(views: [heading, address, scroll, workspaceControls, profileLabel, statusLabel])
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
            workspaceControls.widthAnchor.constraint(equalTo: stack.widthAnchor),
            workspaceRow.widthAnchor.constraint(equalTo: workspaceControls.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func render() {
        let state = runtime.state
        let workspace = state.currentWorkspace
        root.layer?.backgroundColor = accent.withAlphaComponent(0.09).cgColor
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
            } else {
                let menu = NSMenu()
                // Keep the explicit live-page gate: AppKit's automatic target
                // validation would otherwise re-enable this action.
                menu.autoenablesItems = false
                let update = ActionMenuItem(title: "Update Saved URL") { [weak self] in
                    guard let self else { return }
                    // Resolve the latest committed destination at invocation;
                    // the page may navigate after this menu was constructed.
                    self.perform { self.runtime.updateSavedURL(page.id) }
                }
                update.toolTip = "Use this page’s current address when reopening it."
                update.isEnabled = runtime.canUpdateSavedURL(page.id) && page.savedURL != page.lastURL
                menu.addItem(update)
                let unsave = ActionMenuItem(title: page.kind == .pinned ? "Unpin" : "Remove from Favorites") { [weak self] in
                    guard let self else { return }
                    self.perform { self.runtime.makeTemporary(page.id) }
                }
                unsave.toolTip = "Keep this page as a tab in this workspace."
                unsave.isEnabled = !runtime.pendingClose.contains(where: { $0.entryID == page.id })
                menu.addItem(unsave)
                select.menu = menu
            }
            if let menu = select.menu {
                // Boundary actions stay disabled for every entry kind.
                menu.autoenablesItems = false
                menu.addItem(.separator())
                let moveUp = ActionMenuItem(title: "Move Up") { [weak self] in
                    guard let self else { return }
                    self.perform { self.runtime.moveEntry(page.id, direction: .up) }
                }
                moveUp.isEnabled = runtime.state.canMoveEntry(page.id, direction: .up)
                menu.addItem(moveUp)
                let moveDown = ActionMenuItem(title: "Move Down") { [weak self] in
                    guard let self else { return }
                    self.perform { self.runtime.moveEntry(page.id, direction: .down) }
                }
                moveDown.isEnabled = runtime.state.canMoveEntry(page.id, direction: .down)
                menu.addItem(moveDown)
                if page.kind != .favorite {
                    menu.addItem(.separator())
                    let transfer = NSMenuItem(title: "Move to Workspace", action: nil, keyEquivalent: "")
                    let destinations = NSMenu()
                    destinations.autoenablesItems = false
                    let workspace = runtime.state.currentWorkspace
                    let isClosing = runtime.pendingClose.contains(where: { $0.entryID == page.id })
                    for destination in runtime.state.workspaces
                        where destination.id != workspace.id && destination.profileID == workspace.profileID {
                        let destinationID = destination.id
                        let item = ActionMenuItem(title: destination.name) { [weak self] in
                            guard let self else { return }
                            self.perform { self.runtime.moveEntry(page.id, toWorkspace: destinationID) }
                        }
                        item.isEnabled = !isClosing && runtime.state.canMoveEntry(page.id, toWorkspace: destinationID)
                        destinations.addItem(item)
                    }
                    transfer.submenu = destinations
                    transfer.isEnabled = destinations.items.contains(where: \.isEnabled)
                    menu.addItem(transfer)
                }
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

    @objc private func showWorkspaceActions() {
        guard hasStarted, workspaceEditor == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let id = runtime.state.activeWorkspaceID
        requestNativeFocus?()
        let menu = NSMenu()
        menu.autoenablesItems = false
        // Capture the workspace, not its position or a later active selection.
        // The runtime revalidates its position when the action is invoked.
        let moveUp = ActionMenuItem(title: "Move Workspace Up") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.moveWorkspace(id, direction: .up) }
        }
        moveUp.isEnabled = runtime.state.canMoveWorkspace(id, direction: .up)
        menu.addItem(moveUp)
        let moveDown = ActionMenuItem(title: "Move Workspace Down") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.moveWorkspace(id, direction: .down) }
        }
        moveDown.isEnabled = runtime.state.canMoveWorkspace(id, direction: .down)
        menu.addItem(moveDown)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: workspaceActions.bounds.minY), in: workspaceActions)
    }

    private func editWorkspace() {
        guard hasStarted, workspaceEditor == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let workspace = runtime.state.currentWorkspace
        requestNativeFocus?()
        // Capture the identity now: later page callbacks must not redirect an
        // already-open editor to a different workspace.
        let editor = WorkspaceEditor(name: workspace.name, color: workspace.color) { [weak self] name, color in
            guard let self else { return "The workspace is no longer available." }
            guard self.runtime.updateWorkspace(workspace.id, name: name, color: color) else {
                switch self.runtime.lastError {
                case .saveFailed: return "Changes couldn’t be saved. Reopen Bato to reload organization."
                case .unsupportedProfile: return "This Profile isn’t connected to the browser yet."
                default: return "The workspace couldn’t be updated. Check its name and try again."
                }
            }
            self.render()
            return nil
        }
        workspaceEditor = editor
        guard let sheet = editor.window else { workspaceEditor = nil; return }
        window.beginSheet(sheet) { [weak self] _ in
            self?.workspaceEditor = nil
        }
        editor.focusName()
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
    var keyEquivalentsEnabled = true
    var newTab: (() -> Void)?
    var closeSelection: (() -> Void)?
    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Bato workspace sidebar" }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard keyEquivalentsEnabled, modifiers == .command else {
            return super.performKeyEquivalent(with: event)
        }
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

/// Uses a sheet-local draft: Cancel never publishes organization changes.
@MainActor
private final class WorkspaceEditor: NSWindowController {
    private let nameField = NSTextField(string: "")
    private let colorPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let save: (String, String) -> String?
    private var colors: [String] = []

    init(name: String, color: String, save: @escaping (String, String) -> String?) {
        self.save = save
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Edit workspace"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        nameField.stringValue = name
        nameField.setAccessibilityLabel("Workspace name")
        nameField.setAccessibilityIdentifier("bato-workspace-name")
        nameField.cell?.sendsActionOnEndEditing = false
        colorPicker.setAccessibilityLabel("Workspace color")
        colorPicker.setAccessibilityIdentifier("bato-workspace-color")
        let palette = [("Rose", "#B47879"), ("Ocean", "#527FAD"), ("Sage", "#6D8B70"),
                       ("Lavender", "#8975A8"), ("Amber", "#B38847"), ("Slate", "#76818F")]
        for (title, value) in palette {
            colorPicker.addItem(withTitle: title)
            colors.append(value)
        }
        if let index = colors.firstIndex(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) {
            colorPicker.selectItem(at: index)
            // Preserve the original stored representation unless changed.
            colors[index] = color
        } else {
            colorPicker.addItem(withTitle: "Current color (\(color))")
            colors.append(color)
            colorPicker.selectItem(at: colors.count - 1)
        }
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityIdentifier("bato-workspace-edit-error")
        let cancel = ActionButton(title: "Cancel") { [weak self] in self?.dismiss(.cancel) }
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier("bato-workspace-edit-cancel")
        let apply = ActionButton(title: "Save") { [weak self] in self?.saveDraft() }
        apply.keyEquivalent = "\r"
        apply.setAccessibilityIdentifier("bato-workspace-edit-save")
        window.defaultButtonCell = apply.cell as? NSButtonCell
        let spacer = NSView()
        let buttons = NSStackView(views: [spacer, cancel, apply])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [NSTextField(labelWithString: "Name"), nameField,
                                      NSTextField(labelWithString: "Color"), colorPicker,
                                      errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
                nameField.widthAnchor.constraint(equalTo: stack.widthAnchor),
                colorPicker.widthAnchor.constraint(equalTo: stack.widthAnchor),
                errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    func focusName() {
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    private func saveDraft() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorLabel.stringValue = "Enter a workspace name."
            focusName()
            return
        }
        let index = colorPicker.indexOfSelectedItem
        guard colors.indices.contains(index) else { return }
        if let error = save(name, colors[index]) {
            errorLabel.stringValue = error
        } else {
            dismiss(.OK)
        }
    }

    private func dismiss(_ response: NSApplication.ModalResponse) {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window, returnCode: response)
        window.orderOut(nil)
    }
}

@MainActor
private func workspaceColor(_ hex: String) -> NSColor {
    // Documents are validated before presentation; fallback is defensive only.
    guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else {
        return .controlAccentColor
    }
    return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                   green: CGFloat((value >> 8) & 255) / 255,
                   blue: CGFloat(value & 255) / 255, alpha: 1)
}
