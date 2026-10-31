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
    /// The Chromium host schedules committed page work on its CEF UI task runner.
    public var requestPagePresentation: (() -> Void)?
    public var focusTarget: NSView { addressField }

    private let addressField = NSTextField(string: "")
    private let entries = SidebarEntries()
    private let workspacePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let workspaceActions = NSButton(frame: .zero)
    private let profileLabel = NSTextField(labelWithString: "")
    private let workspaceTitle = NSTextField(labelWithString: "")
    private let addressSurface = SidebarSurface()
    private var pageControls: [UUID: (select: NSButton, close: NSButton)] = [:]
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var workspaceIDs: [UUID] = []
    private var hasStarted = false
    private var workspaceEditor: WorkspaceEditor?
    private var pageFinder: PageFinder?
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

    /// Called by the host after leaving AppKit's sheet callback context.
    public func resumeCommittedSelection() {
        guard hasStarted, let window = root.window else { return }
        guard window.attachedSheet == nil, NSApp.modalWindow == nil else {
            render()
            statusLabel.stringValue = "Close the dialog, then select the page to open it."
            statusLabel.isHidden = false
            return
        }
        logPagePresentationFocus("before", window: window)
        // Ending our sheet can leave the owned parent inactive. Restore that
        // window and its native focus before asking the guarded host to create.
        window.makeKeyAndOrderFront(nil)
        requestNativeFocus?()
        logPagePresentationFocus("after", window: window)
        _ = runtime.start()
        render()
    }

    private func logPagePresentationFocus(_ phase: String, window: NSWindow) {
        let event: [String: Any] = ["event": "page-presentation-focus", "phase": phase,
                                    "appActive": NSApp.isActive,
                                    "keyWindow": window.isKeyWindow,
                                    "mainWindow": window.isMainWindow]
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else { return }
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data([0x0A]))
    }

    public func closeSelection() {
        guard let id = runtime.state.currentWorkspace.activeEntryID else { return }
        perform { runtime.closeEntry(id) }
    }

    private func configureView() {
        root.setAccessibilityIdentifier("bato-workspace-sidebar")
        if let view = root as? WorkspaceRoot {
            view.newTab = { [weak self] in self?.newTab() }
            view.closeSelection = { [weak self] in self?.closeSelection() }
        }

        let title = NSTextField(labelWithString: "bato")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        workspaceTitle.font = .systemFont(ofSize: 11, weight: .medium)
        workspaceTitle.textColor = .secondaryLabelColor
        workspaceTitle.lineBreakMode = .byTruncatingTail
        workspaceTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let identity = NSStackView(views: [title, workspaceTitle])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 1
        identity.setContentHuggingPriority(.defaultLow, for: .horizontal)
        workspaceTitle.widthAnchor.constraint(lessThanOrEqualTo: identity.widthAnchor).isActive = true
        let workspaceEdit = ActionButton(title: "") { [weak self] in self?.editWorkspace() }
        configureIcon(workspaceEdit, symbol: "paintpalette", label: "Edit workspace")
        workspaceEdit.setAccessibilityIdentifier("bato-edit-workspace")
        workspaceEdit.toolTip = "Edit workspace name and color"
        workspaceActions.target = self
        workspaceActions.action = #selector(showWorkspaceActions)
        configureIcon(workspaceActions, symbol: "ellipsis", label: "Workspace actions")
        workspaceActions.setAccessibilityIdentifier("bato-workspace-actions")
        workspaceActions.toolTip = "Reorder this workspace"
        let heading = NSStackView(views: [identity, workspaceEdit, workspaceActions])
        heading.orientation = .horizontal
        heading.distribution = .fill
        heading.spacing = 2

        addressField.placeholderString = "Enter a website address"
        addressField.font = .systemFont(ofSize: 12)
        addressField.isBordered = false
        addressField.drawsBackground = false
        addressField.focusRingType = .exterior
        addressField.setAccessibilityLabel("New tab address")
        addressField.setAccessibilityIdentifier("bato-new-tab-address")
        addressField.delegate = self
        addressField.target = self
        addressField.action = #selector(submitAddress)
        // Return submits explicitly; moving focus must not resubmit the address.
        addressField.cell?.sendsActionOnEndEditing = false
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let add = ActionButton(title: "") { [weak self] in self?.submitAddress() }
        configureIcon(add, symbol: "arrow.up.right", label: "Open address in new tab")
        add.setAccessibilityIdentifier("bato-new-tab")
        let addressRow = NSStackView(views: [addressField, add])
        addressRow.orientation = .horizontal
        addressRow.spacing = 4
        addressRow.translatesAutoresizingMaskIntoConstraints = false
        addressSurface.addSubview(addressRow)
        NSLayoutConstraint.activate([
            addressRow.leadingAnchor.constraint(equalTo: addressSurface.leadingAnchor, constant: 10),
            addressRow.trailingAnchor.constraint(equalTo: addressSurface.trailingAnchor, constant: -4),
            addressRow.centerYAnchor.constraint(equalTo: addressSurface.centerYAnchor),
            addressSurface.heightAnchor.constraint(equalToConstant: 36)
        ])
        let new = ActionButton(title: "New tab") { [weak self] in self?.newTab() }
        configureTextAction(new, symbol: "plus")
        new.setAccessibilityIdentifier("bato-focus-new-tab")
        let find = ActionButton(title: "Find page") { [weak self] in self?.findPage() }
        configureTextAction(find, symbol: "magnifyingglass")
        find.setAccessibilityLabel("Find Page")
        find.setAccessibilityIdentifier("bato-find-page")
        let pageActions = NSStackView(views: [new, find])
        pageActions.orientation = .horizontal
        pageActions.distribution = .fillEqually
        pageActions.spacing = 6

        entries.orientation = .vertical
        entries.alignment = .leading
        entries.spacing = 5
        entries.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
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
        workspacePicker.font = .systemFont(ofSize: 12, weight: .medium)
        workspacePicker.controlSize = .small
        workspacePicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        workspacePicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let workspaceAdd = ActionButton(title: "") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.addWorkspace(name: "Workspace \(self.runtime.state.workspaces.count + 1)") }
        }
        configureIcon(workspaceAdd, symbol: "plus", label: "New workspace")
        workspaceAdd.setAccessibilityIdentifier("bato-add-workspace")
        let workspaceRow = NSStackView(views: [workspacePicker, workspaceAdd])
        workspaceRow.orientation = .horizontal
        workspaceRow.spacing = 6
        let profileIcon = NSImageView(image: sidebarSymbol("person.crop.circle", size: 13))
        profileIcon.contentTintColor = .secondaryLabelColor
        profileIcon.setAccessibilityElement(false)
        profileLabel.font = .systemFont(ofSize: 11)
        profileLabel.textColor = .secondaryLabelColor
        profileLabel.lineBreakMode = .byTruncatingTail
        profileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let profileRow = NSStackView(views: [profileIcon, profileLabel])
        profileRow.orientation = .horizontal
        profileRow.spacing = 6
        let footer = NSStackView(views: [workspaceRow, profileRow])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 8
        let separator = NSBox()
        separator.boxType = .separator
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("bato-workspace-status")

        let stack = NSStackView(views: [heading, addressSurface, pageActions, scroll, separator, footer, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            addressSurface.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pageActions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            workspaceRow.widthAnchor.constraint(equalTo: footer.widthAnchor),
            profileRow.widthAnchor.constraint(equalTo: footer.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func configureIcon(_ button: NSButton, symbol: String, label: String) {
        button.title = ""
        button.image = sidebarSymbol(symbol, size: 13)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .recessed
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func configureTextAction(_ button: NSButton, symbol: String) {
        button.image = sidebarSymbol(symbol, size: 12)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.bezelStyle = .recessed
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.heightAnchor.constraint(equalToConstant: 29).isActive = true
    }

    private func render() {
        let state = runtime.state
        let workspace = state.currentWorkspace
        (root as? WorkspaceRoot)?.accent = accent
        addressSurface.accent = accent
        workspaceTitle.stringValue = workspace.name
        let focusedControl = pageControls.first { _, controls in
            root.window?.firstResponder === controls.select || root.window?.firstResponder === controls.close
        }.map { (id: $0.key, close: root.window?.firstResponder === $0.value.close) }
        pageControls.removeAll()
        for view in entries.arrangedSubviews {
            entries.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let favorites = state.profiles.first(where: { $0.id == workspace.profileID })?.favorites ?? []
        addSection("Favorites", pages: favorites)
        addSection("Pinned", pages: workspace.pins)
        addSection("Tabs", pages: workspace.tabs)
        if let focusedControl, let controls = pageControls[focusedControl.id] {
            root.window?.makeFirstResponder(focusedControl.close ? controls.close : controls.select)
        }
        workspaceIDs = state.workspaces.map(\.id)
        workspacePicker.removeAllItems()
        workspacePicker.addItems(withTitles: state.workspaces.map(\.name))
        if let index = workspaceIDs.firstIndex(of: state.activeWorkspaceID) { workspacePicker.selectItem(at: index) }
        profileLabel.stringValue = state.profiles.first(where: { $0.id == workspace.profileID })?.name ?? ""
        pageFinder?.refresh()
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
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
    }

    private func addSection(_ title: String, pages: [PageEntry]) {
        // Shared Favorites deserve space when present, without three empty
        // diagnostic sections competing with a new workspace's first tab.
        guard !pages.isEmpty || title == "Tabs" else { return }
        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.spacing = 6
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let count = NSTextField(labelWithString: String(pages.count))
        count.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        count.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        heading.addArrangedSubview(label)
        heading.addArrangedSubview(spacer)
        heading.addArrangedSubview(count)
        entries.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: entries.widthAnchor, constant: -8).isActive = true
        entries.setCustomSpacing(8, after: heading)
        if pages.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No tabs yet.\nOpen a website to start browsing.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.setAccessibilityIdentifier("bato-empty-tabs")
            entries.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: entries.widthAnchor, constant: -12).isActive = true
        }
        if title == "Favorites" {
            for start in stride(from: 0, to: pages.count, by: 2) {
                let row = NSStackView()
                row.orientation = .horizontal
                row.distribution = .fillEqually
                row.spacing = 6
                for page in pages[start..<min(start + 2, pages.count)] {
                    row.addArrangedSubview(makePageView(page, tile: true))
                }
                if row.arrangedSubviews.count == 1 { row.addArrangedSubview(NSView()) }
                entries.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
            }
        } else {
            for page in pages {
                let row = makePageView(page, tile: false)
                entries.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
            }
        }
        if let last = entries.arrangedSubviews.last { entries.setCustomSpacing(17, after: last) }
    }

    private func makePageView(_ page: PageEntry, tile: Bool) -> NSView {
        let title = page.title.isEmpty ? (page.lastURL.host ?? "Page") : page.title
        let select = ActionButton(title: title) { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.selectEntry(page.id) }
        }
        select.isBordered = false
        select.bezelStyle = .recessed
        select.alignment = tile ? .center : .left
        select.font = .systemFont(ofSize: tile ? 11 : 13, weight: tile ? .medium : .regular)
        select.image = sidebarSymbol(page.kind == .favorite ? "star.fill" : page.kind == .pinned ? "pin.fill" : "globe", size: tile ? 16 : 12)
        select.imagePosition = tile ? .imageAbove : .imageLeading
        select.imageHugsTitle = true
        select.contentTintColor = .labelColor
        select.setButtonType(.momentaryPushIn)
        select.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        select.setContentHuggingPriority(.defaultLow, for: .horizontal)
        (select.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        select.setAccessibilityIdentifier("bato-page-\(page.id.uuidString)")
        select.setAccessibilityLabel(title)
        select.toolTip = "\(title)\n\(page.lastURL.absoluteString)"
        configurePageMenu(select, page: page)
        let close = ActionButton(title: "") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.closeEntry(page.id) }
        }
        close.image = sidebarSymbol("xmark", size: 9)
        close.imagePosition = .imageOnly
        close.isBordered = false
        close.bezelStyle = .recessed
        close.contentTintColor = .secondaryLabelColor
        close.setAccessibilityLabel(page.kind == .temporary ? "Close \(title)" : "Unload \(title)")
        close.setAccessibilityIdentifier("bato-close-\(page.id.uuidString)")
        close.toolTip = page.kind == .temporary ? "Close tab" : "Unload saved page"
        close.isEnabled = !runtime.pendingClose.contains(where: { $0.entryID == page.id })
        // Small borderless close controls stay present for keyboard and AX access;
        // hover changes the surface, never the set of available actions.
        let row = SidebarPageView(select: select, close: close, tile: tile,
                                  selected: runtime.state.currentWorkspace.activeEntryID == page.id,
                                  accent: accent)
        pageControls[page.id] = (select, close)
        return row
    }

    private func configurePageMenu(_ select: NSButton, page: PageEntry) {
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
            statusLabel.isHidden = false
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

    private func findPage() {
        guard hasStarted, pageFinder == nil, workspaceEditor == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        requestNativeFocus?()
        let finder = PageFinder(search: { [weak self] query in
            self?.runtime.state.searchPages(matching: query) ?? []
        }, open: { [weak self] result in
            guard let self else { return "The page is no longer available." }
            guard self.runtime.activateEntry(result.entryID, inWorkspace: result.workspaceID,
                                             deferPageSelection: true) else {
                switch self.runtime.lastError {
                case .saveFailed: return "Changes couldn’t be saved. Reopen Bato to reload organization."
                default: return "This page is no longer available or is closing. Choose another page."
                }
            }
            self.render()
            return nil
        })
        pageFinder = finder
        guard let sheet = finder.window else { pageFinder = nil; return }
        window.beginSheet(sheet) { [weak self] response in
            guard let self else { return }
            self.pageFinder = nil
            if response == .OK {
                // AppKit can still be in its modal context inside this completion.
                // Leave the completion, then let the Chromium host post to its UI task runner.
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.root.window === window else { return }
                    if let request = self.requestPagePresentation {
                        request()
                    } else {
                        self.resumeCommittedSelection()
                    }
                }
            }
        }
        finder.focusSearch()
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

/// Resolve semantic colors while drawing, rather than caching appearance-bound
/// CGColors. Display-option changes redraw the same opaque native surfaces.
@MainActor
private class AdaptiveSidebarView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        // Selector observers are zeroing references on supported macOS versions.
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    @objc private func displayOptionsChanged() { needsDisplay = true }
}

@MainActor
private final class SidebarSurface: AdaptiveSidebarView {
    var accent: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        (NSColor.controlBackgroundColor.blended(withFraction: 0.05, of: accent) ?? .controlBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private final class SidebarPageView: AdaptiveSidebarView {
    private let selected: Bool
    private let accent: NSColor
    private let tile: Bool
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(select: NSButton, close: NSButton, tile: Bool, selected: Bool, accent: NSColor) {
        self.selected = selected
        self.accent = accent
        self.tile = tile
        super.init(frame: .zero)
        select.translatesAutoresizingMaskIntoConstraints = false
        close.translatesAutoresizingMaskIntoConstraints = false
        addSubview(select)
        addSubview(close)
        heightAnchor.constraint(equalToConstant: tile ? 62 : 34).isActive = true
        close.widthAnchor.constraint(equalToConstant: 20).isActive = true
        close.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if tile {
            NSLayoutConstraint.activate([
                select.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
                select.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
                select.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                select.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
                close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                close.topAnchor.constraint(equalTo: topAnchor, constant: 1)
            ])
        } else {
            NSLayoutConstraint.activate([
                select.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
                select.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -2),
                select.topAnchor.constraint(equalTo: topAnchor),
                select.bottomAnchor.constraint(equalTo: bottomAnchor),
                close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
                close.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
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
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        if selected {
            (NSColor.controlBackgroundColor.blended(withFraction: contrast ? 0.3 : 0.2, of: accent) ?? .selectedControlColor).setFill()
        } else if hovered {
            NSColor.quaternaryLabelColor.setFill()
        } else if tile {
            NSColor.controlBackgroundColor.withAlphaComponent(0.65).setFill()
        } else {
            NSColor.clear.setFill()
        }
        path.fill()
        if selected || (contrast && tile) {
            (selected ? accent : NSColor.separatorColor).setStroke()
            path.lineWidth = contrast ? 1.5 : 0.65
            path.stroke()
        }
    }
}

@MainActor
private func sidebarSymbol(_ name: String, size: CGFloat) -> NSImage {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: size, height: size))
    return image.withSymbolConfiguration(.init(pointSize: size, weight: .regular)) ?? image
}

@MainActor
private final class SidebarEntries: NSStackView {
    // NSClipView uses the document's coordinate direction when its height is
    // shorter than the viewport. Top-origin content stays below address entry
    // instead of being bottom-aligned above the workspace footer.
    override var isFlipped: Bool { true }
}

@MainActor
private final class WorkspaceRoot: AdaptiveSidebarView {
    var accent: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let base = NSColor.windowBackgroundColor
        // Opaque, understated workspace color remains readable with Reduce
        // Transparency and adapts to the system's current light/dark palette.
        let fraction: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.04 : 0.11
        let top = base.blended(withFraction: fraction, of: accent) ?? base
        let bottom = base.blended(withFraction: fraction * 0.4, of: accent) ?? base
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)
    }
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

/// Searches organization without creating pages until the user opens a result.
@MainActor
private final class PageFinder: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let searchField = NSSearchField(string: "")
    private let table = PageSearchTable()
    private let resultLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let search: (String) -> [PageSearchResult]
    private let open: (PageSearchResult) -> String?
    private var results: [PageSearchResult] = []

    init(search: @escaping (String) -> [PageSearchResult], open: @escaping (PageSearchResult) -> String?) {
        self.search = search
        self.open = open
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Find Page"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        searchField.placeholderString = "Search page titles, addresses or workspaces"
        searchField.setAccessibilityLabel("Find page search")
        searchField.setAccessibilityIdentifier("bato-page-search")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.cell?.sendsActionOnEndEditing = false
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 50
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityLabel("Matching pages")
        table.setAccessibilityIdentifier("bato-page-search-results")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.openSelection = { [weak self] in self?.openSelected() }
        table.cancel = { [weak self] in self?.dismiss(.cancel) }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        scroll.borderType = .bezelBorder
        resultLabel.font = .systemFont(ofSize: 11)
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.setAccessibilityIdentifier("bato-page-search-count")
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityIdentifier("bato-page-search-error")
        let cancel = ActionButton(title: "Cancel") { [weak self] in self?.dismiss(.cancel) }
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier("bato-page-search-cancel")
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openSelected)
        openButton.keyEquivalent = "\r"
        openButton.setAccessibilityIdentifier("bato-page-search-open")
        panel.defaultButtonCell = openButton.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, openButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [searchField, resultLabel, scroll, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
                searchField.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
                errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func refresh() {
        let selectedID = results.indices.contains(table.selectedRow) ? results[table.selectedRow].entryID : nil
        results = search(searchField.stringValue)
        table.reloadData()
        if let index = results.firstIndex(where: { $0.entryID == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !results.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        openButton.isEnabled = results.indices.contains(table.selectedRow)
        resultLabel.stringValue = results.isEmpty ? "No matching pages." : "\(results.count) \(results.count == 1 ? "page" : "pages") in this Profile"
    }

    func controlTextDidChange(_ notification: Notification) {
        errorLabel.stringValue = ""
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)):
            openSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(.cancel)
        default: return false
        }
        return true
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let row = max(0, min(results.count - 1, table.selectedRow + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        openButton.isEnabled = results.indices.contains(table.selectedRow)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let result = results[row]
        let title = NSTextField(labelWithString: result.entry.title.isEmpty ? result.entry.lastURL.absoluteString : result.entry.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: "\(result.workspaceName) · \(result.entry.lastURL.absoluteString)")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        let cell = NSTableCellView()
        cell.textField = title
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return cell
    }

    @objc private func openSelected() {
        guard results.indices.contains(table.selectedRow) else { return }
        // Snapshot stable identities before the runtime publishes refreshed results.
        let result = results[table.selectedRow]
        if let error = open(result) {
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
private final class PageSearchTable: NSTableView {
    var openSelection: (() -> Void)?
    var cancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: openSelection?()
        case 53: cancel?()
        default: super.keyDown(with: event)
        }
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
