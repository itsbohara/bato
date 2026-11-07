import AppKit
import BatoCore
import BatoPersistence
import BatoRuntime

/// The native sidebar only. Chromium owns page views, origin UI and browser data.
/// The caller must wire the engine's event sink before calling `start()`.
@MainActor
public final class NativeWorkspaceController: NSObject {
    public let root: NSView
    public let runtime: PageRuntime
    public var requestNativeFocus: (() -> Void)?
    /// Window geometry belongs to the host, including the page reservation.
    public var requestSidebarToggle: (() -> Void)? {
        didSet { sidebarToggle.isHidden = requestSidebarToggle == nil }
    }
    /// The Chromium host schedules committed page work on its CEF UI task runner.
    public var requestPagePresentation: (() -> Void)?
    /// The first control a hidden-sidebar keyboard path lands on; it is always present, unlike the toggle.
    public var focusTarget: NSView { newTabButton }
    public var isPeekPresented: Bool { runtime.peekSession.preview != nil }

    private let entries = SidebarEntries()
    private let workspacePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let workspaceActions = NSButton(frame: .zero)
    private let sidebarToggle = NSButton(frame: .zero)
    private let profileLabel = NSTextField(labelWithString: "")
    private lazy var newTabButton = ActionButton(title: "New tab") { [weak self] in self?.newTab() }
    private var pageControls: [UUID: (select: NSButton, close: NSButton)] = [:]
    private var folderControls: [UUID: (disclosure: NSButton, title: NSButton, actions: NSButton)] = [:]
    private var pageIcons: [UUID: NSImage] = [:]
    private var splitControls: [String: NSButton] = [:]
    private let peekRow = NSStackView()
    private let peekLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var workspaceIDs: [UUID] = []
    private var hasStarted = false
    private var sheetObserver: NSObjectProtocol?
    private var workspaceEditor: WorkspaceEditor?
    private var folderEditor: FolderEditor?
    private var pageFinder: PageFinder?
    private let organizationStore: OrganizationStore<BrowserState>
    private var arcImport: ArcImportController?
    private var commandBar: CommandBarController?
    private var commandBarSearchProvider: CommandBarSearchProvider = .duckDuckGo
    private var pendingCommandBarAction: (action: CommandBarAction, query: String)?
    private weak var pendingCommandBarWindow: NSWindow?
    private var commandBarNavigationTarget: LivePage?
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
        organizationStore = store
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
        sheetObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndSheetNotification, object: root.window, queue: .main) { [weak self] _ in
            // Let the sheet finish detaching before the engine is asked to select or close.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.runtime.retryAbandonedPreviews() } }
        }
        _ = runtime.start()
        render()
    }

    public func receive(_ event: PageEvent) {
        switch event {
        case .closed(let page), .unloaded(let page), .creationFailed(let page):
            // A saved entry reopens its saved URL, which can differ from the
            // last live origin. Late terminal events must not clear a newer icon.
            if runtime.livePages[page.entryID] == page { pageIcons.removeValue(forKey: page.entryID) }
        default: break
        }
        runtime.receive(event)
        render()
    }

    /// Icons arrive only through the engine's current live-page generation.
    /// They are session-local presentation data, never organization or a fetch.
    public func receivePageIcon(entryID: UUID, png: Data?) {
        let state = runtime.state
        guard state.profiles.contains(where: { $0.favorites.contains(where: { $0.id == entryID }) }) ||
              state.workspaces.contains(where: { ($0.pins + $0.tabs).contains(where: { $0.id == entryID }) }) else { return }
        if let png, !png.isEmpty, png.count <= 262_144, let image = NSImage(data: png) {
            image.isTemplate = false
            pageIcons[entryID] = image
        } else {
            pageIcons.removeValue(forKey: entryID)
        }
        render()
    }

    /// Opens native navigation, organization search and browser commands.
    public func newTab() { showCommandBar() }

    private func showCommandBar(query: String = "", error: String? = nil, navigating target: LivePage? = nil) {
        guard hasStarted, commandBar == nil, pendingCommandBarAction == nil, pageFinder == nil, workspaceEditor == nil, folderEditor == nil,
              let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        runtime.endPeek()
        requestNativeFocus?()
        commandBarNavigationTarget = target
        let bar = CommandBarController(query: query, error: error,
                                       provider: commandBarSearchProvider,
                                       providerChanged: { [weak self] in self?.commandBarSearchProvider = $0 }) { [weak self] query in
            guard let self else { return [] }
            return CommandBarResults.make(query: query, state: self.runtime.state,
                                          provider: self.commandBarSearchProvider,
                                          navigatingCurrentPage: target != nil).filter { result in
                switch result.action {
                case .command(.toggleSidebar): return self.requestSidebarToggle != nil
                case .command(.closePage): return self.runtime.state.currentWorkspace.activeEntryID != nil
                case .peek: return self.runtime.canOpenPeek
                default: return true
                }
            }
        }
        commandBar = bar
        guard let sheet = bar.window else { commandBar = nil; commandBarNavigationTarget = nil; return }
        window.beginSheet(sheet) { [weak self, weak bar, weak window] response in
            guard let self else { return }
            if response == .OK, let bar, let action = bar.chosenAction {
                self.pendingCommandBarAction = (action, bar.query)
                self.pendingCommandBarWindow = window
            }
            self.commandBar = nil
            guard response == .OK else { self.commandBarNavigationTarget = nil; return }
            // Do not create/select/close a Chromium page inside sheet completion.
            // The host restores its native slot before this scheduled callback.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self else { return }
                guard let window, self.root.window === window else {
                    self.commandBarNavigationTarget = nil
                    self.pendingCommandBarAction = nil
                    self.pendingCommandBarWindow = nil
                    return
                }
                if let request = self.requestPagePresentation { request() }
                else { self.resumeCommittedSelection() }
            }
        }
        bar.focusSearch()
    }

    private func executeCommandBarAction(_ pending: (action: CommandBarAction, query: String)) {
        let succeeded: Bool
        let navigationTarget = commandBarNavigationTarget
        commandBarNavigationTarget = nil
        var retryTarget: LivePage?
        switch pending.action {
        case .open(let url):
            // An engine failure may follow a successful save: do not create a
            // duplicate entry if the new page is already in organization.
            let before = runtime.state
            let opened = runtime.addTab(url: url, title: url.host ?? "New tab")
            succeeded = opened || runtime.state != before
        case .navigateCurrent(let url):
            retryTarget = navigationTarget
            succeeded = navigationTarget.map { runtime.perform(.load(url), on: $0) } ?? false
        case .peek(let url):
            succeeded = runtime.openPeek(url: url)
        case .activate(let result):
            succeeded = runtime.activateEntry(result.entryID, inWorkspace: result.workspaceID)
        case .command(let command):
            switch command {
            case .findPage: findPage()
            case .toggleSidebar: requestSidebarToggle?()
            case .closePage: closeSelection()
            }
            return
        }
        render()
        if !succeeded {
            let message = runtime.lastError == .saveFailed
                ? "Changes couldn’t be saved. Reopen Bato to reload organization."
                : "This page is unavailable or is closing. Choose another result."
            showCommandBar(query: pending.query, error: message, navigating: retryTarget)
        }
    }

    /// Called by the host after leaving AppKit's sheet callback context.
    public func resumeCommittedSelection() {
        // A rejected or stale presentation callback cancels its intent. It must
        // neither block the next CmdT nor execute on an unrelated later callback.
        let pending = pendingCommandBarAction
        let owner = pendingCommandBarWindow
        pendingCommandBarAction = nil
        pendingCommandBarWindow = nil
        guard hasStarted, let window = root.window else { return }
        if pending != nil, owner !== window { return }
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
        if let pending {
            executeCommandBarAction(pending)
        } else {
            _ = runtime.start()
            render()
        }
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

    /// Escape and the Close control both land here; Chromium may confirm before closing.
    public func dismissPeek() {
        perform { runtime.dismissPeek() }
    }

    public func dismissPeek(preview: LivePage) {
        perform { runtime.dismissPeek(preview: preview) }
    }

    public func promotePeek() {
        perform { runtime.promotePeek() }
    }

    public func openPeek(from parent: LivePage, url: URL) {
        perform { runtime.openPeek(from: parent, url: url) }
    }

    @objc private func toggleSidebar() { requestSidebarToggle?() }

    /// Opens the command bar on the current URL to navigate this page instead of opening a tab.
    /// False when no live page can be navigated, so the host leaves the key to Chromium.
    @discardableResult
    public func editAddress() -> Bool {
        guard hasStarted, let target = runtime.navigationTarget,
              let url = runtime.state.visibleEntries.first(where: { $0.id == target.entryID })?.lastURL else { return false }
        showCommandBar(query: url.absoluteString, navigating: target)
        return commandBar != nil
    }

    /// Copies the selected live page's latest URL; false when there is no such page or it is not copyable.
    @discardableResult
    public func copyCurrentLink() -> Bool {
        guard runtime.navigationTarget != nil, let entryID = runtime.state.currentWorkspace.activeEntryID else { return false }
        return copyLink(entryID: entryID, workspaceID: runtime.state.activeWorkspaceID,
                        profileID: runtime.state.currentWorkspace.profileID)
    }

    private func configureView() {
        root.setAccessibilityIdentifier("bato-workspace-sidebar")
        if let view = root as? WorkspaceRoot {
            view.newTab = { [weak self] in self?.newTab() }
            view.closeSelection = { [weak self] in self?.closeSelection() }
            view.editAddress = { [weak self] in self?.editAddress() ?? false }
            view.copyLink = { [weak self] in self?.copyCurrentLink() ?? false }
        }

        let workspaceEdit = ActionButton(title: "") { [weak self] in self?.editWorkspace() }
        configureIcon(workspaceEdit, symbol: "paintpalette", label: "Edit workspace")
        workspaceEdit.setAccessibilityIdentifier("bato-edit-workspace")
        workspaceEdit.toolTip = "Edit workspace name and color"
        workspaceActions.target = self
        workspaceActions.action = #selector(showWorkspaceActions)
        configureIcon(workspaceActions, symbol: "ellipsis", label: "Workspace actions")
        workspaceActions.setAccessibilityIdentifier("bato-workspace-actions")
        workspaceActions.toolTip = "Reorder this workspace"
        sidebarToggle.target = self
        sidebarToggle.action = #selector(toggleSidebar)
        configureIcon(sidebarToggle, symbol: "sidebar.left", label: "Toggle sidebar")
        sidebarToggle.setAccessibilityIdentifier("bato-toggle-sidebar")
        sidebarToggle.toolTip = "Toggle sidebar (⌘S)"
        sidebarToggle.isHidden = requestSidebarToggle == nil
        let headingSpacer = NSView()
        headingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let heading = NSStackView(views: [sidebarToggle, headingSpacer, workspaceEdit, workspaceActions])
        heading.orientation = .horizontal
        heading.distribution = .fill
        heading.spacing = 2

        configureTextAction(newTabButton, symbol: "plus")
        newTabButton.setAccessibilityIdentifier("bato-focus-new-tab")
        let find = ActionButton(title: "Find page") { [weak self] in self?.findPage() }
        configureTextAction(find, symbol: "magnifyingglass")
        find.setAccessibilityLabel("Find Page")
        find.setAccessibilityIdentifier("bato-find-page")
        peekLabel.font = .systemFont(ofSize: 11, weight: .medium)
        peekLabel.textColor = .secondaryLabelColor
        peekLabel.lineBreakMode = .byTruncatingTail
        peekLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        peekLabel.setAccessibilityIdentifier("bato-peek-title")
        let promote = ActionButton(title: "Open as Tab") { [weak self] in self?.promotePeek() }
        configureTextAction(promote, symbol: "arrow.up.left.and.arrow.down.right")
        promote.setAccessibilityIdentifier("bato-peek-promote")
        let closePeek = ActionButton(title: "Close") { [weak self] in self?.dismissPeek() }
        configureTextAction(closePeek, symbol: "xmark")
        closePeek.toolTip = "Close Peek (Esc)"
        closePeek.setAccessibilityIdentifier("bato-peek-close")
        let peekActions = NSStackView(views: [promote, closePeek])
        peekActions.orientation = .horizontal
        peekActions.distribution = .fillEqually
        peekActions.spacing = 6
        peekRow.setViews([peekLabel, peekActions], in: .leading)
        peekRow.orientation = .vertical
        peekRow.alignment = .leading
        peekRow.spacing = 4
        peekRow.isHidden = true
        peekLabel.widthAnchor.constraint(equalTo: peekRow.widthAnchor).isActive = true
        peekActions.widthAnchor.constraint(equalTo: peekRow.widthAnchor).isActive = true
        let pageActions = NSStackView(views: [newTabButton, find])
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

        let stack = NSStackView(views: [heading, pageActions, peekRow, scroll, separator, footer, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: SidebarMetrics.sideInset),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -SidebarMetrics.sideInset),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pageActions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            peekRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
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
        commandBar?.refresh()
        let state = runtime.state
        let workspace = state.currentWorkspace
        (root as? WorkspaceRoot)?.accent = accent
        let focusedControl = pageControls.first { _, controls in
            root.window?.firstResponder === controls.select || root.window?.firstResponder === controls.close
        }.map { (id: $0.key, close: root.window?.firstResponder === $0.value.close) }
        let focusedFolder = folderControls.compactMap { id, controls -> (id: UUID, role: Int)? in
            let ordered = [controls.disclosure, controls.title, controls.actions]
            guard let role = ordered.firstIndex(where: { root.window?.firstResponder === $0 }) else { return nil }
            return (id, role)
        }.first
        let focusedSplit = splitControls.first { root.window?.firstResponder === $0.value }?.key
        splitControls.removeAll()
        let parentOfFocusedPin = focusedControl.flatMap { workspace.folder(containingPin: $0.id)?.id }
        pageControls.removeAll()
        folderControls.removeAll()
        let existingIDs = Set(state.profiles.flatMap { $0.favorites.map(\.id) } +
                              state.workspaces.flatMap { ($0.pins + $0.tabs).map(\.id) })
        pageIcons = pageIcons.filter { existingIDs.contains($0.key) }
        for view in entries.arrangedSubviews {
            entries.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let favorites = state.profiles.first(where: { $0.id == workspace.profileID })?.favorites ?? []
        if let split = state.currentSplit { addActiveSplit(split, workspaceID: workspace.id) }
        addSavedSplits(workspaceID: workspace.id)
        addSection("Favorites", pages: favorites)
        let filedIDs = Set(workspace.folders.flatMap(\.pinIDs))
        addSection("Pinned", pages: workspace.pins.filter { !filedIDs.contains($0.id) },
                   totalCount: workspace.pins.count, includeEmpty: !workspace.folders.isEmpty)
        for folder in workspace.subfolders(of: nil) { addFolder(folder, depth: 1, workspace: workspace) }
        addSection("Tabs", pages: workspace.tabs)
        if let focusedControl, let controls = pageControls[focusedControl.id] {
            root.window?.makeFirstResponder(focusedControl.close ? controls.close : controls.select)
        } else if let focusedSplit, let control = splitControls[focusedSplit] {
            root.window?.makeFirstResponder(control)
        } else if let focusedFolder, let controls = folderControls[focusedFolder.id] {
            let ordered = [controls.disclosure, controls.title, controls.actions]
            root.window?.makeFirstResponder(ordered[focusedFolder.role])
        } else if let parentOfFocusedPin, let controls = folderControls[parentOfFocusedPin] {
            root.window?.makeFirstResponder(controls.disclosure)
        }
        workspaceIDs = state.workspaces.map(\.id)
        workspacePicker.removeAllItems()
        workspacePicker.addItems(withTitles: state.workspaces.map(\.name))
        if let index = workspaceIDs.firstIndex(of: state.activeWorkspaceID) { workspacePicker.selectItem(at: index) }
        profileLabel.stringValue = state.profiles.first(where: { $0.id == workspace.profileID })?.name ?? ""
        pageFinder?.refresh()
        let peek = runtime.peekSession.preview
        peekRow.isHidden = peek == nil
        peekLabel.stringValue = peek.map { "Peek · " + ($0.title.isEmpty ? ($0.url.host ?? $0.url.absoluteString) : $0.title) } ?? ""
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

    /// Split controls address organization identities, never Chromium tab indices.
    private func canRunSplitAction(in workspaceID: UUID) -> Bool {
        guard hasStarted, runtime.supportsSplits,
              runtime.state.activeWorkspaceID == workspaceID,
              commandBar == nil, pendingCommandBarAction == nil, pageFinder == nil,
              workspaceEditor == nil, folderEditor == nil,
              let window = root.window, window.attachedSheet == nil,
              NSApp.modalWindow == nil else { return false }
        return true
    }

    private func splitTitle(_ split: PageSplit) -> String {
        let pages = runtime.state.currentWorkspace.pins + runtime.state.currentWorkspace.tabs
        let left = pages.first { $0.id == split.leftEntryID }
        let right = pages.first { $0.id == split.rightEntryID }
        return "\(left.map(pageTitle) ?? "Page") + \(right.map(pageTitle) ?? "Page")"
    }

    private func pageTitle(_ page: PageEntry) -> String {
        page.title.isEmpty ? (page.lastURL.host ?? "Page") : page.title
    }

    private func addActiveSplit(_ split: PageSplit, workspaceID: UUID) {
        let heading = NSTextField(labelWithString: "Split view")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        entries.addArrangedSubview(heading)
        let pages = runtime.state.currentWorkspace.pins + runtime.state.currentWorkspace.tabs
        let isClosing = runtime.pendingClose.contains { $0.entryID == split.leftEntryID || $0.entryID == split.rightEntryID }
        let sides = NSStackView()
        sides.orientation = .horizontal
        sides.distribution = .fillEqually
        sides.spacing = 4
        for (position, entryID) in [("left", split.leftEntryID), ("right", split.rightEntryID)] {
            guard let page = pages.first(where: { $0.id == entryID }) else { continue }
            let button = ActionButton(title: pageTitle(page)) { [weak self] in
                guard let self, self.canRunSplitAction(in: workspaceID),
                      self.runtime.state.currentWorkspace.splits.contains(where: { $0.id == split.id }) else { return }
                self.perform { self.runtime.activateSplit(split.id, focusedEntryID: entryID) }
            }
            configureTextAction(button, symbol: position == "left" ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled")
            button.contentTintColor = runtime.state.currentWorkspace.activeEntryID == entryID ? accent : .secondaryLabelColor
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            button.setAccessibilityLabel("Focus \(position) page: \(pageTitle(page))")
            let key = "bato-split-\(position)-\(split.id.uuidString)"
            button.setAccessibilityIdentifier(key)
            splitControls[key] = button
            button.isEnabled = !isClosing
            sides.addArrangedSubview(button)
        }
        entries.addArrangedSubview(sides)
        sides.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 4
        if !split.isPinned {
            let pin = ActionButton(title: "Pin pair") { [weak self] in
                guard let self, self.canRunSplitAction(in: workspaceID) else { return }
                self.perform { self.runtime.pinSplit(split.id) }
            }
            configureTextAction(pin, symbol: "pin")
            pin.toolTip = "Save both destinations as a pinned pair."
            pin.isEnabled = !isClosing
            let key = "bato-pin-split-\(split.id.uuidString)"
            pin.setAccessibilityIdentifier(key)
            splitControls[key] = pin
            actions.addArrangedSubview(pin)
        }
        let separate = ActionButton(title: "Separate") { [weak self] in
            guard let self, self.canRunSplitAction(in: workspaceID) else { return }
            self.perform { split.isPinned ? self.runtime.deactivateSplit() : self.runtime.dissolveSplit(split.id) }
        }
        configureTextAction(separate, symbol: "rectangle.split.2x1")
        separate.toolTip = split.isPinned ? "Show the focused page alone. The saved pair remains available." : "Separate the pages. Both pages remain available."
        separate.setAccessibilityLabel("Separate split")
        separate.isEnabled = !isClosing
        let key = "bato-separate-split-\(split.id.uuidString)"
        separate.setAccessibilityIdentifier(key)
        splitControls[key] = separate
        actions.addArrangedSubview(separate)
        let optionsKey = "bato-split-options-\(split.id.uuidString)"
        let options = ActionButton(title: "") { [weak self] in
            guard let self, let anchor = self.splitControls[optionsKey] else { return }
            self.showSplitOptions(split.id, workspaceID: workspaceID, anchor: anchor)
        }
        configureIcon(options, symbol: "ellipsis", label: "Split options")
        options.setAccessibilityIdentifier(optionsKey)
        options.toolTip = "Adjust split widths"
        options.isEnabled = !isClosing
        splitControls[optionsKey] = options
        actions.addArrangedSubview(options)
        entries.addArrangedSubview(actions)
        if let last = entries.arrangedSubviews.last { entries.setCustomSpacing(14, after: last) }
    }

    private func showSplitOptions(_ splitID: UUID, workspaceID: UUID, anchor: NSView) {
        guard canRunSplitAction(in: workspaceID),
              let split = runtime.state.currentSplit, split.id == splitID,
              !runtime.pendingClose.contains(where: { $0.entryID == split.leftEntryID || $0.entryID == split.rightEntryID }) else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, adjustment) in [("Widen Left Page", 0.1), ("Equal Width", 0.0), ("Widen Right Page", -0.1)] {
            let item = ActionMenuItem(title: title) { [weak self] in
                guard let self, self.canRunSplitAction(in: workspaceID),
                      let current = self.runtime.state.currentSplit, current.id == splitID,
                      !self.runtime.pendingClose.contains(where: { $0.entryID == current.leftEntryID || $0.entryID == current.rightEntryID }) else { return }
                let ratio = adjustment == 0 ? 0.5 : min(0.9, max(0.1, current.dividerRatio + adjustment))
                self.perform { self.runtime.updateSplitRatio(splitID, ratio: ratio) }
            }
            let target = adjustment == 0 ? 0.5 : min(0.9, max(0.1, split.dividerRatio + adjustment))
            item.isEnabled = abs(target - split.dividerRatio) > 0.0001
            menu.addItem(item)
        }
        requestNativeFocus?()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    private func addSavedSplits(workspaceID: UUID) {
        let splits = runtime.state.currentWorkspace.splits.filter(\.isPinned)
        guard !splits.isEmpty else { return }
        let heading = NSTextField(labelWithString: "Saved pairs")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        entries.addArrangedSubview(heading)
        for split in splits {
            let button = ActionButton(title: splitTitle(split)) { [weak self] in
                guard let self, self.canRunSplitAction(in: workspaceID) else { return }
                self.perform { self.runtime.activateSplit(split.id) }
            }
            configureTextAction(button, symbol: "rectangle.split.2x1")
            button.alignment = .left
            button.contentTintColor = runtime.state.currentWorkspace.activeSplitID == split.id ? accent : .secondaryLabelColor
            let isClosing = runtime.pendingClose.contains { $0.entryID == split.leftEntryID || $0.entryID == split.rightEntryID }
            button.isEnabled = runtime.supportsSplits && !isClosing
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            let key = "bato-saved-split-\(split.id.uuidString)"
            button.setAccessibilityIdentifier(key)
            button.setAccessibilityLabel("Open saved pair: \(splitTitle(split))")
            splitControls[key] = button
            let menu = NSMenu()
            menu.autoenablesItems = false
            let remove = ActionMenuItem(title: "Remove Split Pair") { [weak self] in
                guard let self, self.canRunSplitAction(in: workspaceID) else { return }
                self.perform { self.runtime.dissolveSplit(split.id) }
            }
            remove.toolTip = "Keep both pages and remove only the pair."
            remove.isEnabled = !isClosing
            menu.addItem(remove)
            button.menu = menu
            entries.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
        }
        if let last = entries.arrangedSubviews.last { entries.setCustomSpacing(14, after: last) }
    }

    private func addSection(_ title: String, pages: [PageEntry], totalCount: Int? = nil, includeEmpty: Bool = false) {
        // Shared Favorites deserve space when present, without three empty
        // diagnostic sections competing with a new workspace's first tab.
        guard !pages.isEmpty || title == "Tabs" || includeEmpty else { return }
        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.spacing = 6
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let count = NSTextField(labelWithString: String(totalCount ?? pages.count))
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
        if pages.isEmpty && title == "Tabs" {
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
        if let icon = pageIcons[page.id]?.copy() as? NSImage {
            icon.size = NSSize(width: tile ? 20 : 16, height: tile ? 20 : 16)
            select.image = icon
            select.imageScaling = .scaleProportionallyDown
        } else {
            select.image = sidebarSymbol(page.kind == .favorite ? "star.fill" : page.kind == .pinned ? "pin.fill" : "globe", size: tile ? 16 : 12)
        }
        select.imagePosition = tile ? .imageAbove : .imageLeading
        select.imageHugsTitle = true
        select.contentTintColor = pageIcons[page.id] == nil ? .labelColor : nil
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
            let workspaceID = runtime.state.activeWorkspaceID
            let profileID = runtime.state.currentWorkspace.profileID
            let entryID = page.id
            let copy = ActionMenuItem(title: "Copy Link") { [weak self] in
                self?.copyLink(entryID: entryID, workspaceID: workspaceID, profileID: profileID)
            }
            copy.toolTip = "Copy this page’s current address."
            copy.setAccessibilityIdentifier("bato-copy-link-\(entryID.uuidString)")
            copy.isEnabled = !runtime.pendingClose.contains(where: { $0.entryID == entryID })
            menu.addItem(.separator())
            menu.addItem(copy)
            if runtime.supportsSplits, page.kind != .favorite {
                let workspaceID = runtime.state.activeWorkspaceID
                let sourceID = runtime.state.currentWorkspace.activeEntryID
                let split = ActionMenuItem(title: "Split with Current Page") { [weak self] in
                    guard let self, self.canRunSplitAction(in: workspaceID),
                          self.runtime.state.currentWorkspace.activeEntryID == sourceID,
                          self.runtime.state.canCreateSplit(with: page.id) else { return }
                    self.perform { self.runtime.createSplit(with: page.id) }
                }
                split.isEnabled = runtime.state.canCreateSplit(with: page.id) &&
                    !runtime.pendingClose.contains(where: { $0.entryID == page.id || $0.entryID == sourceID })
                menu.addItem(.separator())
                menu.addItem(split)
            }
            if page.kind == .pinned {
                menu.addItem(.separator())
                let workspace = runtime.state.currentWorkspace
                let workspaceID = workspace.id
                let currentFolderID = workspace.folder(containingPin: page.id)?.id
                let isClosing = runtime.pendingClose.contains(where: { $0.entryID == page.id })
                let move = NSMenuItem(title: "Move to Folder", action: nil, keyEquivalent: "")
                let folders = NSMenu()
                folders.autoenablesItems = false
                for (folder, depth) in workspace.folderOutline() {
                    let folderID = folder.id
                    let item = ActionMenuItem(title: folder.name) { [weak self] in
                        guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return }
                        self.perform { self.runtime.movePin(page.id, toFolder: folderID) }
                    }
                    item.indentationLevel = depth - 1
                    item.state = currentFolderID == folderID ? .on : .off
                    item.isEnabled = !isClosing && currentFolderID != folderID
                    folders.addItem(item)
                }
                move.submenu = folders
                move.isEnabled = folders.items.contains(where: \.isEnabled)
                menu.addItem(move)
                if currentFolderID != nil {
                    let unfile = ActionMenuItem(title: "Remove from Folder") { [weak self] in
                        guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return }
                        self.perform { self.runtime.movePin(page.id, toFolder: nil) }
                    }
                    unfile.isEnabled = !isClosing
                    menu.addItem(unfile)
                }
            }
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

    @discardableResult
    private func copyLink(entryID: UUID, workspaceID: UUID, profileID: UUID) -> Bool {
        guard hasStarted, runtime.state.activeWorkspaceID == workspaceID,
              runtime.state.currentWorkspace.profileID == profileID,
              commandBar == nil, pendingCommandBarAction == nil, pageFinder == nil,
              workspaceEditor == nil, folderEditor == nil,
              let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil,
              !runtime.pendingClose.contains(where: { $0.entryID == entryID }),
              let entry = runtime.state.visibleEntries.first(where: { $0.id == entryID }),
              let scheme = entry.lastURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = entry.lastURL.host, !host.isEmpty,
              entry.lastURL.user == nil, entry.lastURL.password == nil else { return false }
        // Resolve at invocation: saved entries may have navigated since the menu
        // was built, and their saved destination must remain unchanged.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.lastURL.absoluteString, forType: .string)
        return true
    }

    private static let folderIndent: CGFloat = 12

    private func addIndented(_ view: NSView, leading: CGFloat) {
        let inset = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        inset.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: leading),
            view.trailingAnchor.constraint(equalTo: inset.trailingAnchor),
            view.topAnchor.constraint(equalTo: inset.topAnchor),
            view.bottomAnchor.constraint(equalTo: inset.bottomAnchor)
        ])
        entries.addArrangedSubview(inset)
        inset.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
    }

    private func addFolder(_ folder: PageFolder, depth: Int, workspace: Workspace) {
        let workspaceID = workspace.id
        let folderID = folder.id
        let indent = CGFloat(depth - 1) * Self.folderIndent
        let accessibleName = depth > 1 ? "\(folder.name), level \(depth)" : folder.name
        let pinCount = workspace.pinCount(inFolder: folderID)
        let toggle: () -> Void = { [weak self] in
            guard let self, self.runtime.state.activeWorkspaceID == workspaceID,
                  let current = self.runtime.state.currentWorkspace.folder(folderID) else { return }
            self.perform { self.runtime.setFolderCollapsed(folderID, collapsed: !current.isCollapsed) }
        }
        let disclosure = ActionButton(title: "", invoke: toggle)
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.onOff)
        disclosure.state = folder.isCollapsed ? .off : .on
        disclosure.setAccessibilityLabel("\(folder.isCollapsed ? "Expand" : "Collapse") \(accessibleName)")
        disclosure.setAccessibilityIdentifier("bato-folder-disclosure-\(folderID.uuidString)")
        disclosure.widthAnchor.constraint(equalToConstant: 16).isActive = true
        disclosure.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let title = ActionButton(title: folder.name, invoke: toggle)
        title.image = sidebarSymbol(folder.isCollapsed ? "folder" : "folder.fill", size: 12)
        title.imagePosition = .imageLeading
        title.imageHugsTitle = true
        title.isBordered = false
        title.alignment = .left
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.contentTintColor = .secondaryLabelColor
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        (title.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        title.setAccessibilityLabel(accessibleName)
        title.setAccessibilityIdentifier("bato-folder-\(folderID.uuidString)")
        title.toolTip = "\(folder.name) · \(pinCount) pinned pages"
        let count = NSTextField(labelWithString: String(pinCount))
        count.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        count.textColor = .secondaryLabelColor
        let actions = ActionButton(title: "") { [weak self, weak title] in
            guard let title else { return }
            self?.showFolderActions(folderID, workspaceID: workspaceID, anchor: title)
        }
        configureIcon(actions, symbol: "ellipsis", label: "Folder actions for \(accessibleName)")
        actions.setAccessibilityIdentifier("bato-folder-actions-\(folderID.uuidString)")
        let heading = NSStackView(views: [disclosure, title, count, actions])
        heading.spacing = 3
        heading.orientation = .horizontal
        if depth == 1 {
            entries.addArrangedSubview(heading)
            heading.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
        } else {
            addIndented(heading, leading: indent)
        }
        folderControls[folderID] = (disclosure, title, actions)
        title.menu = folderMenu(folderID, workspaceID: workspaceID)
        if !folder.isCollapsed {
            for pinID in folder.pinIDs {
                guard let pin = workspace.pins.first(where: { $0.id == pinID }) else { continue }
                addIndented(makePageView(pin, tile: false), leading: 14 + indent)
            }
            for child in workspace.subfolders(of: folderID) {
                addFolder(child, depth: depth + 1, workspace: workspace)
            }
        }
        if depth == 1, let last = entries.arrangedSubviews.last { entries.setCustomSpacing(9, after: last) }
    }

    private func folderMenu(_ folderID: UUID, workspaceID: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let state = runtime.state
        let workspace = state.currentWorkspace
        let isActive = state.activeWorkspaceID == workspaceID
        let depth = workspace.depth(ofFolder: folderID) ?? 1
        let newSubfolder = ActionMenuItem(title: "New Subfolder…") { [weak self] in
            guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return }
            self.editFolder(parentID: folderID)
        }
        newSubfolder.isEnabled = isActive && depth < BrowserState.maxFolderDepth
        menu.addItem(newSubfolder)
        menu.addItem(ActionMenuItem(title: "Rename Folder…") { [weak self] in
            guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return }
            self.editFolder(folderID)
        })
        menu.addItem(.separator())
        for (label, direction) in [("Move Folder Up", FolderMoveDirection.up), ("Move Folder Down", .down)] {
            let move = ActionMenuItem(title: label) { [weak self] in
                guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return }
                self.perform { self.runtime.moveFolder(folderID, direction: direction) }
            }
            move.isEnabled = isActive && state.canMoveFolder(folderID, direction: direction)
            menu.addItem(move)
        }
        let moveInto = NSMenuItem(title: "Move into Folder", action: nil, keyEquivalent: "")
        let destinations = NSMenu()
        destinations.autoenablesItems = false
        let destinationItem = { [weak self] (title: String, parentID: UUID?, level: Int) -> ActionMenuItem in
            let item = ActionMenuItem(title: title) {
                guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return }
                self.perform { self.runtime.moveFolder(folderID, toParent: parentID) }
            }
            item.indentationLevel = level
            item.isEnabled = isActive && state.canMoveFolder(folderID, toParent: parentID)
            return item
        }
        if workspace.folder(folderID)?.parentID != nil {
            destinations.addItem(destinationItem("Top Level", nil, 0))
        }
        for (candidate, level) in workspace.folderOutline() where candidate.id != folderID {
            destinations.addItem(destinationItem(candidate.name, candidate.id, level - 1))
        }
        moveInto.submenu = destinations
        moveInto.isEnabled = destinations.items.contains(where: \.isEnabled)
        menu.addItem(moveInto)
        menu.addItem(.separator())
        let dissolve = ActionMenuItem(title: "Dissolve Folder") { [weak self] in
            guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return }
            self.perform { self.runtime.dissolveFolder(folderID) }
        }
        dissolve.toolTip = "Move its pages and subfolders up one level."
        menu.addItem(dissolve)
        return menu
    }

    private func showFolderActions(_ folderID: UUID, workspaceID: UUID, anchor: NSView) {
        guard hasStarted, runtime.state.activeWorkspaceID == workspaceID,
              runtime.state.currentWorkspace.folder(folderID) != nil,
              let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        requestNativeFocus?()
        folderMenu(folderID, workspaceID: workspaceID).popUp(positioning: nil,
            at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    private func editFolder(_ folderID: UUID? = nil, parentID: UUID? = nil) {
        guard hasStarted, folderEditor == nil, workspaceEditor == nil, pageFinder == nil,
              commandBar == nil, pendingCommandBarAction == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let workspaceID = runtime.state.activeWorkspaceID
        let folder = folderID.flatMap { runtime.state.currentWorkspace.folder($0) }
        if folderID != nil && folder == nil { return }
        if let parentID, runtime.state.currentWorkspace.folder(parentID) == nil { return }
        requestNativeFocus?()
        let editor = FolderEditor(name: folder?.name ?? "", creating: folderID == nil, subfolder: parentID != nil) { [weak self] name in
            guard let self, self.runtime.state.activeWorkspaceID == workspaceID else { return "The workspace is no longer active." }
            let saved = folderID.map { self.runtime.renameFolder($0, name: name) }
                ?? self.runtime.createFolder(name: name, parentID: parentID)
            guard saved else {
                return self.runtime.lastError == .saveFailed
                    ? "Changes couldn’t be saved. Reopen Bato to reload organization."
                    : "Enter a folder name using 1–80 characters without control characters."
            }
            self.render()
            return nil
        }
        folderEditor = editor
        guard let sheet = editor.window else { folderEditor = nil; return }
        window.beginSheet(sheet) { [weak self] _ in self?.folderEditor = nil }
        editor.focusName()
    }

    private func perform(_ command: () -> Bool) {
        guard hasStarted else { return }
        _ = command()
        render()
    }

    @objc private func showWorkspaceActions() {
        guard hasStarted, workspaceEditor == nil, folderEditor == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let id = runtime.state.activeWorkspaceID
        requestNativeFocus?()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: "New Folder…") { [weak self] in
            guard let self, self.runtime.state.activeWorkspaceID == id else { return }
            self.editFolder()
        })
        menu.addItem(ActionMenuItem(title: "Import from Arc…") { [weak self] in self?.importFromArc() })
        menu.addItem(.separator())
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

    private func importFromArc() {
        guard hasStarted, arcImport == nil, pageFinder == nil, workspaceEditor == nil, folderEditor == nil,
              let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        requestNativeFocus?()
        let flow = ArcImportController(window: window, store: organizationStore, runtime: runtime) { [weak self] in
            self?.arcImport = nil
            self?.render()
        }
        arcImport = flow
        flow.begin()
    }

    private func findPage() {
        guard hasStarted, pageFinder == nil, workspaceEditor == nil, folderEditor == nil, let window = root.window,
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
        guard hasStarted, workspaceEditor == nil, folderEditor == nil, let window = root.window,
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
class AdaptiveSidebarView: NSView {
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
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: SidebarMetrics.cornerRadius, yRadius: SidebarMetrics.cornerRadius)
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

/// One radius and one side inset for every sidebar surface, so rows and the pill read as a set.
enum SidebarMetrics {
    static let cornerRadius: CGFloat = 10
    static let sideInset: CGFloat = 10
}

@MainActor
func sidebarSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: size, height: size))
    return image.withSymbolConfiguration(.init(pointSize: size, weight: weight)) ?? image
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
    var editAddress: (() -> Bool)?
    var copyLink: (() -> Bool)?
    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Bato workspace sidebar" }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let key = event.charactersIgnoringModifiers?.lowercased()
        guard keyEquivalentsEnabled else { return super.performKeyEquivalent(with: event) }
        switch (modifiers, key) {
        case (.command, "t"): newTab?(); return true
        case (.command, "w"): closeSelection?(); return true
        case (.command, "l"): if editAddress?() == true { return true }
        case ([.command, .shift], "c"): if copyLink?() == true { return true }
        default: break
        }
        return super.performKeyEquivalent(with: event)
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

/// A local metadata draft; cancellation never changes organization or pages.
@MainActor
private final class FolderEditor: NSWindowController {
    private let field = NSTextField(string: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let save: (String) -> String?
    init(name: String, creating: Bool, subfolder: Bool = false, save: @escaping (String) -> String?) {
        self.save = save
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = creating ? (subfolder ? "New Subfolder" : "New Folder") : "Rename Folder"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        field.stringValue = name
        field.placeholderString = "Folder name"
        field.setAccessibilityLabel("Folder name")
        field.setAccessibilityIdentifier("bato-folder-name")
        field.cell?.sendsActionOnEndEditing = false
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityIdentifier("bato-folder-edit-error")
        let cancel = ActionButton(title: "Cancel") { [weak self] in self?.dismiss(.cancel) }
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier("bato-folder-edit-cancel")
        let apply = ActionButton(title: creating ? "Create" : "Save") { [weak self] in self?.saveDraft() }
        apply.keyEquivalent = "\r"
        apply.setAccessibilityIdentifier("bato-folder-edit-save")
        panel.defaultButtonCell = apply.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, apply])
        buttons.spacing = 8
        let stack = NSStackView(views: [NSTextField(labelWithString: "Name"), field, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
                field.widthAnchor.constraint(equalTo: stack.widthAnchor),
                errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    func focusName() { window?.makeFirstResponder(field); field.selectText(nil) }
    private func saveDraft() {
        if let error = save(field.stringValue) { errorLabel.stringValue = error }
        else { dismiss(.OK) }
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
