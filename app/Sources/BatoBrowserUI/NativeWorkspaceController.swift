import AppKit
import BatoBlocking
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
    private let workspacePager = NSStackView()
    private let workspaceActions = NSButton(frame: .zero)
    private let sidebarToggle = NSButton(frame: .zero)
    private var trafficLightClearanceWidth: NSLayoutConstraint?
    private let profileButton = NSButton(frame: .zero)
    private var downloadsSidebar: DownloadsSidebar?
    private var downloadsProfileKey: (UUID) -> String = { $0.uuidString }
    private let switcherButton = NSButton(frame: .zero)
    private lazy var newTabButton = ActionButton(title: "New tab") { [weak self] in self?.newTab() }
    private lazy var newTabRow = SidebarActionRow(button: newTabButton)
    private var pageControls: [UUID: (select: NSButton, close: NSButton)] = [:]
    private var folderControls: [UUID: (disclosure: NSButton, title: NSButton, actions: NSButton)] = [:]
    private var pageIcons: [UUID: NSImage] = [:]
    private var dropSlotViews: [(view: NSView, kind: SidebarDropSlot.Kind)] = []
    private let entryDragSource = SidebarEntryDragSource()
    private let hoverCard = SidebarHoverCard()
    private let peekRow = NSStackView()
    private let peekLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var hasStarted = false
    /// Set by the Space header just before it changes the model, so the next render can animate the change.
    private var pendingPinsAnimation: PinsAnimation?
    private var pointerInSidebar = false
    private var pinsAnimating = false
    private var renderDeferred = false
    private weak var spaceHeaderRow: SpaceHeaderRow?
    /// The pinned rows and folders as last drawn, so a collapse can fade out a picture of them.
    private var pinnedViews: [NSView] = []
    private weak var tidyClearRow: TidyClearRow?
    private var tabSwitcher: TabSwitcherSession?
    private var tabSwitcherPanel: TabSwitcherPanel?
    private var tabSwitcherTimer: Timer?
    private var tabSwitcherMonitor: Any?
    private var sheetObserver: NSObjectProtocol?
    private var workspaceEditor: WorkspaceEditor?
    private var folderEditor: FolderEditor?
    private var profileEditor: ProfileEditor?
    private var pageFinder: PageFinder?
    private let organizationStore: OrganizationStore<BrowserState>
    private let recovery: RecoveryController
    private var arcImport: ArcImportController?
    private var settingsWindow: SettingsWindowController?
    private let switcherPopover = SwitcherPopover()
    private lazy var archiveController = ArchiveController(
        runtime: runtime, window: { [weak self] in self?.root.window },
        canPresent: { [weak self] in self?.canOpenBrowserPage ?? false },
        restored: { [weak self] in
            guard let self else { return }
            render()
            if let request = requestPagePresentation { request() } else { resumeCommittedSelection() }
        })
    private var commandBar: CommandBarController?
    private let preferences: AppPreferencesStore
    private var commandBarSearchProvider: CommandBarSearchProvider { preferences.current().searchProvider }
    private var pendingCommandBarAction: (action: CommandBarAction, query: String)?
    private weak var pendingCommandBarWindow: NSWindow?
    private var commandBarNavigationTarget: LivePage?
    private var commandBarSplitSide: SplitSide?
    /// The state the list is drawn from; a neighbouring workspace's while its picture is taken for a slide.
    private var previewState: BrowserState?
    private var sidebarState: BrowserState { previewState ?? runtime.state }
    /// A theme being edited in the Create Space page or the theme popover, drawn instead of the stored one.
    private var themePreview: SpaceTheme?
    private var theme: SpaceTheme { themePreview ?? sidebarState.currentWorkspace.effectiveTheme }
    private var accent: NSColor { themePreview?.primaryNSColor ?? workspaceColor(sidebarState.currentWorkspace.color) }
    private let sidebarScroll = SidebarScrollView()
    private var slide: SpaceSlide?
    private var createSpacePage: CreateSpacePageView?
    private var themePopover: SpaceThemePopover?
    private var slideReleasing = false
    private var slideListTop: CGFloat = 0
    private var slideHeight: CGFloat = 0
    private let cardFrames = NSHashTable<ContentCardFrameView>.weakObjects()
    /// One per window; the host adds it above the Chrome views and it follows the workspace tint.
    public func makeCardFrame() -> ContentCardFrameView {
        let frame = ContentCardFrameView(theme: theme)
        frame.showsEmptyState = runtime.state.showsEmptySpace
        frame.onShowSidebar = { [weak self] in self?.requestSidebarToggle?() }
        frame.onAddSplit = { [weak self] side in self?.addSplit(side) }
        frame.onSplitRatio = { [weak self] ratio in
            guard let self, let split = self.runtime.state.currentSplit else { return }
            _ = self.runtime.updateSplitRatio(split.id, ratio: ratio)
        }
        frame.canAddSplit = runtime.supportsSplits && runtime.state.canSplitSelection
        cardFrames.add(frame)
        return frame
    }

    /// Engine hooks for a pane's back, forward, reload and stop; set by the host that owns the pages.
    public var paneNavigator: ((LivePage, PaneNavigationAction) -> Bool)?
    public var paneNavigationState: ((LivePage) -> PaneNavigationState)?
    private let paneOverlays = NSHashTable<SplitPaneOverlayView>.weakObjects()
    /// One per window; shows a native toolbar row over each pane of a displayed pair.
    public func makeSplitPaneOverlay() -> SplitPaneOverlayView {
        let overlay = SplitPaneOverlayView(frame: .zero)
        overlay.provider = { [weak self] in self?.splitPaneStates() ?? [] }
        overlay.actions = SplitPaneActions(
            focus: { [weak self] id in self?.focusPane(id) },
            close: { [weak self] id in self?.perform { self?.runtime.closeEntry(id) ?? false } },
            navigate: { [weak self] id, action in
                guard let self, let page = self.runtime.livePages[id] else { return }
                _ = self.paneNavigator?(page, action)
            },
            addSplit: { [weak self] side in self?.addSplit(side) },
            toggleSidebar: { [weak self] in self?.requestSidebarToggle?() })
        paneOverlays.add(overlay)
        return overlay
    }

    private func splitPaneStates() -> [SplitPaneState] {
        guard let split = runtime.state.currentSplit else { return [] }
        let workspace = runtime.state.currentWorkspace
        let pages = workspace.pins + workspace.tabs
        return [split.leftEntryID, split.rightEntryID].compactMap { id in
            guard let page = pages.first(where: { $0.id == id }) else { return nil }
            let navigation = runtime.livePages[id].flatMap { paneNavigationState?($0) } ?? PaneNavigationState()
            return SplitPaneState(entryID: id, title: pageTitle(page), url: page.lastURL,
                                  isFocused: workspace.activeEntryID == id, navigation: navigation)
        }
    }

    /// The pane that is focused, by index, for the card's outline.
    public var focusedPaneIndex: Int? {
        guard let split = runtime.state.currentSplit,
              let focused = runtime.state.currentWorkspace.activeEntryID else { return nil }
        return SplitPaneChrome.paneIndex(of: focused, in: split)
    }

    private func focusPane(_ id: UUID) {
        guard let split = runtime.state.currentSplit, split.contains(id),
              runtime.state.currentWorkspace.activeEntryID != id, canRunSplitAction(in: runtime.state.activeWorkspaceID) else { return }
        perform { runtime.activateSplit(split.id, focusedEntryID: id) }
    }

    /// Opens the command bar to choose what the new pane on `side` shows (Add Right Split and friends).
    public func addSplit(_ side: SplitSide) {
        guard hasStarted, runtime.supportsSplits, runtime.state.canSplitSelection else { return }
        showCommandBar(splittingTo: side)
    }

    /// Load failures throw without replacing the existing document. The factory
    /// receives the organization's launch Profile, which stays bound to the engine's original context
    /// whichever workspace is selected at startup.
    /// It must not infer engine isolation from this UUID alone.
    /// Hosts with their own scoped keyboard router must disable sidebar key equivalents.
    public init(directory: URL, handlesKeyEquivalents: Bool = true,
                makeEngine: (UUID) throws -> any PageEngine) throws {
        let store = OrganizationStore<BrowserState>(directory: directory, validate: { try $0.validate() })
        let recovery = RecoveryController(directory: directory, store: store)
        recovery.beginLaunch()
        let state: BrowserState
        let loaded = try store.load()
        if let staged = recovery.applyPendingRestore() {
            state = staged
        } else if let restored = loaded {
            state = restored
        } else {
            state = BrowserState.initial()
            try store.save(state)
        }
        let engine = try makeEngine(state.launchProfileID ?? state.currentWorkspace.profileID)
        organizationStore = store
        preferences = AppPreferencesStore(directory: directory)
        self.recovery = recovery
        runtime = try PageRuntime(state: state, engine: engine, commit: { try store.save($0) })
        runtime.snapshotCommit = { _ = try store.saveWithSnapshot($0, named: "pre-delete") }
        let closedTabsStore = ClosedTabsStore(directory: directory)
        runtime.restoreClosedTabs(closedTabsStore.load())
        runtime.closedTabsDidChange = { try? closedTabsStore.save($0) }
        let sidebar = WorkspaceRoot(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        sidebar.keyEquivalentsEnabled = handlesKeyEquivalents
        root = sidebar
        super.init()
        sidebar.windowChanged = { [weak self] in DispatchQueue.main.async { self?.fitTrafficLightClearance() } }
        configureView()
        runtime.onStateChange = { [weak self] _ in self?.render() }
        render()
    }

    /// Call only after attaching the root and wiring the engine callback sink.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        installTabSwitcherMonitor()
        sheetObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndSheetNotification, object: root.window, queue: .main) { [weak self] _ in
            // Let the sheet finish detaching before the engine is asked to select or close.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.runtime.retryAbandonedPreviews() } }
        }
        guard let window = root.window, case .abnormal = recovery.launchStatus else { return finishStart() }
        recovery.presentLaunchOffer(on: window, canAdopt: { [weak self] in self?.runtime.livePages.isEmpty == true },
                                    adopt: { [weak self] in self?.runtime.adoptRestoredOrganization($0) ?? false },
                                    completion: { [weak self] in self?.finishStart() })
    }

    private func finishStart() {
        recovery.captureSessionStart()
        _ = runtime.start()
        render()
        recovery.confirmLaunchSoon()
        if let window = root.window { recovery.showNoticeIfNeeded(on: window) }
        archiveController.start()
        offerUBlockListsOnFirstRun()
    }

    /// Waits for launch sheets to clear, then asks once about the optional uBlock Origin lists.
    private func offerUBlockListsOnFirstRun() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, canOpenBrowserPage, let window = root.window else { return }
            UBlockOffer.offerIfDue(on: window)
        }
    }

    /// Marks this session as ended cleanly; the next launch then offers no recovery.
    public func prepareForQuit() { recovery.prepareForQuit() }

    /// What to show instead of the sidebar when organization can't be opened.
    public static func unavailableMessage(for error: Error) -> String {
        RecoveryController.unavailableMessage(for: error)
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

    /// Browser chords that would otherwise act on Chromium's tab strip or history: they follow the sidebar.
    public func reopenClosedTab(at offset: Int = 0) { performWhenIdle({ runtime.reopenClosedTab(at: offset) }) }
    public func selectAdjacentPage(step: Int) { performWhenIdle({ runtime.selectAdjacentEntry(step: step) }) }
    public func selectPage(shortcut number: Int) { performWhenIdle({ runtime.selectEntry(forShortcut: number) }) }
    public func duplicateSelection() { performWhenIdle({ runtime.duplicateSelectedEntry() }) }
    public func togglePinSelection() { performWhenIdle({ runtime.togglePinSelectedEntry() }) }
    public func closeOtherTemporaryTabs() { performWhenIdle({ runtime.closeOtherTemporaryTabs() }) }
    public var canCloseTemporaryTabsBelowSelection: Bool { runtime.canCloseTemporaryTabsBelowSelection }
    public func closeTemporaryTabsBelowSelection() { performWhenIdle({ runtime.closeTemporaryTabsBelowSelection() }) }

    private func performWhenIdle(_ command: () -> Bool) {
        guard commandBar == nil, pageFinder == nil, root.window?.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        perform(command)
    }

    // MARK: Ctrl-Tab switcher

    private var canSwitchTabs: Bool {
        hasStarted && commandBar == nil && pageFinder == nil && workspaceEditor == nil && folderEditor == nil &&
            root.window?.attachedSheet == nil && NSApp.modalWindow == nil
    }

    /// Ctrl-Tab is taken here, before Chromium, because releasing Control is what commits the choice and only
    /// a monitor sees both. Menus and Cmd-Option-arrows keep stepping through the sidebar.
    private func installTabSwitcherMonitor() {
        guard tabSwitcherMonitor == nil else { return }
        tabSwitcherMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            nonisolated(unsafe) let unsafeEvent = event
            let consumed = MainActor.assumeIsolated { self?.handleTabSwitcher(unsafeEvent) == true }
            return consumed ? nil : event
        }
    }

    private func handleTabSwitcher(_ event: NSEvent) -> Bool {
        guard event.window != nil, event.window === root.window else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.type {
        case .keyDown:
            if tabSwitcher != nil, event.keyCode == 53 { endTabSwitcher(commit: false); return true }
            guard event.keyCode == 48, flags.contains(.control), flags.isDisjoint(with: [.command, .option]) else {
                return tabSwitcher != nil
            }
            advanceTabSwitcher(step: flags.contains(.shift) ? -1 : 1)
            return true
        case .flagsChanged:
            if tabSwitcher != nil, !flags.contains(.control) { endTabSwitcher(commit: true) }
            return false
        default:
            return false
        }
    }

    private func advanceTabSwitcher(step: Int) {
        if tabSwitcher != nil {
            tabSwitcher?.advance(step: step)
            showTabSwitcher()
            return
        }
        guard canSwitchTabs, let session = TabSwitcherSession(items: runtime.tabSwitcherItems(), step: step) else { return }
        tabSwitcher = session
        tabSwitcherTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.tabSwitcher != nil else { return }
                self?.tabSwitcher?.holdElapsed()
                self?.showTabSwitcher()
            }
        }
    }

    private func showTabSwitcher() {
        guard let session = tabSwitcher, session.phase == .showing || tabSwitcherPanel?.isShowing == true, let window = root.window else { return }
        let panel = tabSwitcherPanel ?? TabSwitcherPanel { [weak self] id in self?.switcherContent(for: id) }
        tabSwitcherPanel = panel
        panel.show(session, over: window)
    }

    private func switcherContent(for id: UUID) -> TabSwitchRowContent? {
        guard let page = runtime.state.visibleEntries.first(where: { $0.id == id }) else { return nil }
        let title = pageTitle(page)
        let size = SidebarStyle.rowIconSize + 4
        let icon = (pageIcons[id]?.copy() as? NSImage).map { icon -> NSImage in icon.size = NSSize(width: size, height: size); return icon }
            ?? SidebarStyle.letterIcon(for: title, url: page.lastURL, size: size)
        return TabSwitchRowContent(title: title, host: SidebarHoverCardContent(title: title, url: page.lastURL).host, icon: icon)
    }

    /// Ends the switcher; a commit selects the chosen item, selecting either member of a pair shows both panes.
    private func endTabSwitcher(commit: Bool) {
        guard let session = tabSwitcher else { return }
        tabSwitcher = nil
        tabSwitcherTimer?.invalidate()
        tabSwitcherTimer = nil
        tabSwitcherPanel?.hide()
        tabSwitcherPanel = nil
        guard commit, case .commit(let item) = session.controlReleased(), canSwitchTabs else { return }
        performWhenIdle { runtime.selectEntry(item.selectionEntryID) }
    }

    /// Opens History, Downloads or Chromium's settings as a tab of the current Profile.
    public func openEssential(_ essential: BrowserEssential) {
        guard canOpenBrowserPage else { return }
        runtime.endPeek()
        requestNativeFocus?()
        _ = runtime.openEssential(essential)
        render()
    }

    /// Chromium's site settings for the selected page, as a tab of the current Profile. Reached from
    /// Chromium's page-info "Site settings" link, which would otherwise open a tab Bato doesn't track.
    public func openSiteSettings() {
        guard canOpenBrowserPage else { return }
        let state = runtime.state
        let page = state.visibleEntries.first { $0.id == state.currentWorkspace.activeEntryID }?.lastURL
        runtime.endPeek()
        requestNativeFocus?()
        _ = runtime.openSiteSettings(for: page)
        render()
    }

    /// A web link handed over by macOS (Bato as the default browser) opens as a tab of the current
    /// Workspace, brought to the front. Anything but a plain HTTP(S) address is refused.
    @discardableResult
    public func openExternalURL(_ url: URL) -> Bool {
        guard canOpenBrowserPage, Self.isExternalWebLink(url) else { return false }
        runtime.endPeek()
        let before = runtime.state
        let opened = runtime.addTab(url: url, title: url.host ?? "New tab")
        guard opened || runtime.state != before else { return false }
        root.window?.makeKeyAndOrderFront(nil)
        render()
        return true
    }

    public static func isExternalWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    private var canOpenBrowserPage: Bool {
        guard hasStarted, commandBar == nil, pageFinder == nil, workspaceEditor == nil, folderEditor == nil,
              let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        return true
    }

    /// Opens Bato's own Settings window. It is not tied to a browser window, so it never blocks one.
    public func showSettings(_ pane: SettingsPane? = nil) {
        guard hasStarted else { return }
        let window = settingsWindow ?? SettingsWindowController(hooks: SettingsHooks(
            state: { [weak self] in self?.runtime.state ?? .initial() },
            blockingService: { BlockingHost.shared.service(forProfile: $0) },
            createProfile: { [weak self] in self?.fromBrowserWindow { $0.editProfile(creating: true) } },
            deleteProfile: { [weak self] id in self?.fromBrowserWindow { $0.confirmDeleteProfile(id) } },
            renameCurrentProfile: { [weak self] in self?.fromBrowserWindow { $0.editProfile(creating: false) } },
            importFromArc: { [weak self] in self?.fromBrowserWindow { $0.importFromArc() } },
            openEssential: { [weak self] essential in self?.fromBrowserWindow { $0.openEssential(essential) } },
            defaultBrowser: .system(),
            recovery: recovery,
            setArchivePeriod: { [weak self] in _ = self?.runtime.setArchivePeriod($0) },
            setWorkspaceArchivePeriod: { [weak self] in _ = self?.runtime.setArchivePeriod($1, forWorkspace: $0) },
            openArchive: { [weak self] in self?.fromBrowserWindow { $0.archiveController.show() } },
            searchProvider: { [weak self] in self?.commandBarSearchProvider ?? .default },
            setSearchProvider: { [weak self] in self?.setSearchProvider($0) },
            searchSuggestions: { [weak self] in self?.preferences.current().searchSuggestions ?? true },
            setSearchSuggestions: { [weak self] enabled in
                try? self?.preferences.update { $0.searchSuggestions = enabled }
            }))
        settingsWindow = window
        window.show(pane)
    }

    private func setSearchProvider(_ provider: CommandBarSearchProvider) {
        try? preferences.update { $0.searchProvider = provider }
        settingsWindow?.reload()
    }

    /// Sheets and pages belong to the browser window, so Settings actions bring it forward first.
    private func fromBrowserWindow(_ action: (NativeWorkspaceController) -> Void) {
        root.window?.makeKeyAndOrderFront(nil)
        action(self)
    }

    private func showCommandBar(query: String = "", error: String? = nil, navigating target: LivePage? = nil,
                                splittingTo side: SplitSide? = nil) {
        guard hasStarted, commandBar == nil, pendingCommandBarAction == nil, pageFinder == nil, workspaceEditor == nil, folderEditor == nil,
              let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        runtime.endPeek()
        requestNativeFocus?()
        commandBarNavigationTarget = target
        commandBarSplitSide = side
        let bar = CommandBarController(query: query, error: error,
                                       provider: commandBarSearchProvider,
                                       pageIcon: { [weak self] in self?.pageIcons[$0] },
                                       suggestionsEnabled: { [weak self] in self?.preferences.current().searchSuggestions ?? false }) { [weak self] query, suggestions in
            guard let self else { return [] }
            return CommandBarResults.make(query: query, state: self.runtime.state,
                                          provider: self.commandBarSearchProvider,
                                          navigatingCurrentPage: target != nil,
                                          suggestions: suggestions).filter { result in
                switch result.action {
                case .command(.toggleSidebar): return self.requestSidebarToggle != nil
                case .command(.closePage): return self.runtime.state.currentWorkspace.activeEntryID != nil
                case .command(.archiveTab): return self.selectedTemporaryTabID != nil
                case .peek: return self.runtime.canOpenPeek
                default: return true
                }
            }
        }
        commandBar = bar
        bar.present(over: window, card: { [weak self, weak window] in
            guard let window else { return .zero }
            return self?.cardFrames.allObjects.first { $0.window === window }?.cardRectOnScreen ?? window.frame
        }) { [weak self, weak bar, weak window] response in
            guard let self else { return }
            if response == .OK, let bar, let action = bar.chosenAction {
                self.pendingCommandBarAction = (action, bar.query)
                self.pendingCommandBarWindow = window
            }
            self.commandBar = nil
            guard response == .OK else {
                self.commandBarNavigationTarget = nil
                self.commandBarSplitSide = nil
                self.requestNativeFocus?()
                return
            }
            // Do not create/select/close a Chromium page inside the dismissal callback;
            // the parent window must be key again before the page is created.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self else { return }
                guard let window, self.root.window === window else {
                    self.commandBarNavigationTarget = nil
                    self.commandBarSplitSide = nil
                    self.pendingCommandBarAction = nil
                    self.pendingCommandBarWindow = nil
                    return
                }
                if let request = self.requestPagePresentation { request() }
                else { self.resumeCommittedSelection() }
            }
        }
    }

    private func executeCommandBarAction(_ pending: (action: CommandBarAction, query: String)) {
        let succeeded: Bool
        let navigationTarget = commandBarNavigationTarget
        commandBarNavigationTarget = nil
        let splitSide = commandBarSplitSide
        commandBarSplitSide = nil
        var retryTarget: LivePage?
        switch pending.action {
        case .open(let url):
            // An engine failure may follow a successful save: do not create a
            // duplicate entry if the new page is already in organization.
            let before = runtime.state
            let opened = splitSide.map { runtime.addSplitTab(url: url, title: url.host ?? "New tab", side: $0) }
                ?? runtime.addTab(url: url, title: url.host ?? "New tab")
            succeeded = opened || runtime.state != before
        case .navigateCurrent(let url):
            retryTarget = navigationTarget
            succeeded = navigationTarget.map { runtime.perform(.load(url), on: $0) } ?? false
        case .peek(let url):
            succeeded = runtime.openPeek(url: url)
        case .activate(let result):
            if let splitSide, result.workspaceID == runtime.state.activeWorkspaceID,
               runtime.state.canCreateSplit(with: result.entryID) {
                succeeded = runtime.createSplit(with: result.entryID, side: splitSide)
            } else {
                succeeded = runtime.activateEntry(result.entryID, inWorkspace: result.workspaceID)
            }
        case .command(let command):
            switch command {
            case .findPage: findPage()
            case .toggleSidebar: requestSidebarToggle?()
            case .closePage: closeSelection()
            case .archiveTab: selectedTemporaryTabID.map { id in perform { runtime.archiveTab(id) } }
            case .openArchive: archiveController.show()
            case .openHistory: openEssential(.history)
            case .openDownloads: openEssential(.downloads)
            case .openSettings: showSettings()
            }
            return
        }
        render()
        if !succeeded {
            let message = runtime.lastError == .saveFailed
                ? "Changes couldn’t be saved. Reopen Bato to reload organization."
                : "This page is unavailable or is closing. Choose another result."
            showCommandBar(query: pending.query, error: message, navigating: retryTarget, splittingTo: splitSide)
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

    private var selectedTemporaryTabID: UUID? {
        let workspace = runtime.state.currentWorkspace
        return workspace.tabs.first { $0.id == workspace.activeEntryID }?.id
    }

    public func closeSelection() {
        guard let id = runtime.state.currentWorkspace.activeEntryID else { return }
        if let pair = runtime.state.currentSplit, pair.isPinned {
            perform { runtime.closePinnedPair(pair.id) }
        } else {
            perform { runtime.closeEntry(id) }
        }
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
    public func copyCurrentLink(as format: LinkFormat = .url) -> Bool {
        guard runtime.navigationTarget != nil, let entryID = runtime.state.currentWorkspace.activeEntryID else { return false }
        return copyLink(entryID: entryID, workspaceID: runtime.state.activeWorkspaceID,
                        profileID: runtime.state.currentWorkspace.profileID, format: format)
    }

    /// Rows for the Spaces menu, in the order Control-1…9 follow.
    public var spaceMenuEntries: [SpaceMenuEntry] { runtime.state.spaceMenuEntries }
    /// Called after every render, so the Spaces menu can follow workspace changes.
    public var onSpacesChanged: (() -> Void)?

    public func switchToSpace(_ id: UUID) { switchWorkspace(id) }
    public func switchToAdjacentSpace(next: Bool) { swipeWorkspace(next ? .next : .previous) }
    public func addSpace() { createSpace() }

    /// Each Profile has exactly one window, so a new window can only bring that one forward.
    public func showWindow() {
        guard let window = root.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureView() {
        root.setAccessibilityIdentifier("bato-workspace-sidebar")
        if let view = root as? WorkspaceRoot {
            view.newTab = { [weak self] in self?.newTab() }
            view.closeSelection = { [weak self] in self?.closeSelection() }
            view.editAddress = { [weak self] in self?.editAddress() ?? false }
            view.copyLink = { [weak self] in self?.copyCurrentLink() ?? false }
            view.switchToWorkspace = { [weak self] in self?.switchToShortcut($0) ?? false }
            configureSwipe(view.swipe)
            view.pointerChanged = { [weak self] in self?.setPointerInSidebar($0) }
        }

        workspaceActions.target = self
        workspaceActions.action = #selector(showWorkspaceActions)
        configureIcon(workspaceActions, symbol: "ellipsis", label: "Workspace actions")
        workspaceActions.setAccessibilityIdentifier("bato-workspace-actions")
        workspaceActions.toolTip = "Edit, reorder or import into this workspace"
        sidebarToggle.target = self
        sidebarToggle.action = #selector(toggleSidebar)
        configureIcon(sidebarToggle, symbol: "sidebar.left", label: "Toggle sidebar")
        sidebarToggle.setAccessibilityIdentifier("bato-toggle-sidebar")
        sidebarToggle.toolTip = "Toggle sidebar (⌘S)"
        sidebarToggle.isHidden = requestSidebarToggle == nil
        let trafficLightClearance = WindowDragView()
        let clearanceWidth = trafficLightClearance.widthAnchor.constraint(equalToConstant: SidebarMetrics.trafficLightClearance)
        clearanceWidth.isActive = true
        self.trafficLightClearanceWidth = clearanceWidth
        switcherButton.target = self
        switcherButton.action = #selector(showWorkspaceSwitcher)
        switcherButton.isBordered = false
        switcherButton.bezelStyle = .recessed
        switcherButton.font = .systemFont(ofSize: 13, weight: .semibold)
        switcherButton.contentTintColor = .labelColor
        switcherButton.alignment = .left
        switcherButton.lineBreakMode = .byTruncatingTail
        switcherButton.imagePosition = .imageLeading
        switcherButton.imageHugsTitle = true
        switcherButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        switcherButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        switcherButton.setAccessibilityLabel("Current workspace")
        switcherButton.setAccessibilityHelp("Opens the workspace and Profile switcher. Control-1 to Control-9 switch directly.")
        switcherButton.setAccessibilityIdentifier("bato-space-name")
        let dragSpace = WindowDragView()
        dragSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let heading = NSStackView(views: [trafficLightClearance, switcherButton, dragSpace, sidebarToggle, workspaceActions])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.distribution = .fill
        heading.spacing = 2
        // The toolbar row sits one card margin below the window top, and AppKit centres the traffic lights
        // about 3pt lower than the row's midpoint; measured against the toolbar in a real window.
        heading.edgeInsets = NSEdgeInsets(top: SidebarMetrics.headingDrop, left: 0, bottom: 0, right: 0)
        heading.heightAnchor.constraint(equalToConstant: SidebarMetrics.topRowHeight + SidebarMetrics.headingDrop).isActive = true

        newTabButton.title = "New Tab"
        let plus = sidebarSymbol("plus", size: 13, weight: .medium)
        let iconSize = NSSize(width: SidebarStyle.rowIconSize, height: SidebarStyle.rowIconSize)
        newTabButton.image = NSImage(size: iconSize, flipped: false) { rect in
            plus.draw(in: NSRect(x: rect.midX - plus.size.width / 2, y: rect.midY - plus.size.height / 2,
                                 width: plus.size.width, height: plus.size.height))
            return true
        }
        newTabButton.image?.isTemplate = true
        newTabButton.imagePosition = .imageLeading
        newTabButton.font = SidebarStyle.rowFont
        newTabButton.bezelStyle = .recessed
        newTabButton.isBordered = false
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.alignment = .left
        newTabButton.focusRingType = .none
        newTabButton.setAccessibilityLabel("New Tab")
        newTabButton.setAccessibilityIdentifier("bato-focus-new-tab")
        peekLabel.font = .systemFont(ofSize: 11, weight: .medium)
        peekLabel.textColor = .secondaryLabelColor
        peekLabel.lineBreakMode = .byTruncatingTail
        peekLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        peekLabel.setAccessibilityIdentifier("bato-peek-title")
        let promote = ActionButton(title: "Open as Tab") { [weak self] in self?.promotePeek() }
        configureTextAction(promote, symbol: "arrow.up.left.and.arrow.down.right")
        promote.setAccessibilityIdentifier("bato-peek-promote")
        promote.setAccessibilityLabel("Open Peek as tab")
        promote.setAccessibilityHelp("Keeps the previewed page as a tab in this workspace. Option-Command-Return.")
        let closePeek = ActionButton(title: "Close") { [weak self] in self?.dismissPeek() }
        configureTextAction(closePeek, symbol: "xmark")
        closePeek.toolTip = "Close Peek (Esc)"
        closePeek.setAccessibilityIdentifier("bato-peek-close")
        closePeek.setAccessibilityLabel("Close Peek")
        closePeek.setAccessibilityHelp("Dismisses the preview and returns to the page beneath. Escape.")
        let peekActions = NSStackView(views: [promote, closePeek])
        peekActions.orientation = .horizontal
        peekActions.distribution = .fillEqually
        peekActions.spacing = 6
        peekRow.setViews([peekLabel, peekActions], in: .leading)
        peekRow.orientation = .vertical
        peekRow.alignment = .leading
        peekRow.spacing = 4
        peekRow.isHidden = true
        peekRow.setAccessibilityRole(.group)
        peekRow.setAccessibilityLabel("Peek")
        peekLabel.widthAnchor.constraint(equalTo: peekRow.widthAnchor).isActive = true
        peekActions.widthAnchor.constraint(equalTo: peekRow.widthAnchor).isActive = true

        entries.slotViews = { [weak self] in self?.dropSlotViews ?? [] }
        entryDragSource.onEnded = { [weak self] in self?.entries.setFavoritesZone(visible: false) }
        entries.resolveDrop = { [weak self] id, point in self?.resolveDrop(entryID: id, at: point) }
        entries.performDrop = { [weak self] id, target in self?.performDrop(entryID: id, target: target) ?? false }
        entries.orientation = .vertical
        entries.alignment = .leading
        entries.spacing = 5
        entries.translatesAutoresizingMaskIntoConstraints = false
        let scroll = sidebarScroll
        configureSwipe(scroll.swipe)
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

        workspacePager.orientation = .horizontal
        workspacePager.spacing = 0
        workspacePager.setAccessibilityLabel("Workspace")
        workspacePager.setAccessibilityIdentifier("bato-workspace-picker")
        workspacePager.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let workspaceAdd = ActionButton(title: "") { [weak self] in
            guard let self else { return }
            self.addSpace()
        }
        configureIcon(workspaceAdd, symbol: "plus", label: "New workspace")
        workspaceAdd.setAccessibilityIdentifier("bato-add-workspace")
        let pagerSpacer = NSView()
        pagerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let workspaceRow = NSStackView(views: [workspacePager, pagerSpacer, workspaceAdd])
        workspaceRow.orientation = .horizontal
        workspaceRow.spacing = 6
        profileButton.target = self
        profileButton.action = #selector(showProfileMenu)
        profileButton.isBordered = false
        profileButton.bezelStyle = .recessed
        profileButton.font = .systemFont(ofSize: 11)
        profileButton.contentTintColor = .secondaryLabelColor
        profileButton.alignment = .left
        profileButton.lineBreakMode = .byTruncatingTail
        profileButton.imagePosition = .imageLeading
        profileButton.imageHugsTitle = true
        profileButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        profileButton.setAccessibilityLabel("Profile")
        profileButton.setAccessibilityHelp("Switch, create or rename Profiles")
        profileButton.setAccessibilityIdentifier("bato-profile-button")
        let footer = NSStackView(views: [workspaceRow, profileButton])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 8
        let separator = NSBox()
        separator.boxType = .separator
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("bato-workspace-status")

        let stack = NSStackView(views: [heading, peekRow, scroll, separator, footer, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: SidebarMetrics.sideInset),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -SidebarMetrics.sideInset),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 0),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            peekRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            workspaceRow.widthAnchor.constraint(equalTo: footer.widthAnchor),
            profileButton.widthAnchor.constraint(equalTo: footer.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    /// Mounts the downloads button in the workspace footer row. `profileKey` maps a Profile to the key
    /// the engine tags its downloads with.
    public func attachDownloads(_ controller: DownloadsController, profileKey: @escaping (UUID) -> String = { $0.uuidString }) {
        guard downloadsSidebar == nil, let row = workspacePager.superview as? NSStackView else { return }
        let sidebar = DownloadsSidebar(controller: controller)
        downloadsSidebar = sidebar
        downloadsProfileKey = profileKey
        row.insertArrangedSubview(sidebar.button, at: row.arrangedSubviews.count - 1)
        controller.onChange = { [weak sidebar] in sidebar?.refresh() }
        render()
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
        button.font = SidebarStyle.actionFont
        button.bezelStyle = .recessed
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.heightAnchor.constraint(equalToConstant: 29).isActive = true
    }

    /// Keeps the workspace label clear of the real window buttons, which differ with the system's window style.
    private func fitTrafficLightClearance() {
        guard let constraint = trafficLightClearanceWidth, let window = root.window,
              let zoom = window.standardWindowButton(.zoomButton), let container = zoom.superview else { return }
        let lightsEnd = container.convert(zoom.frame, to: nil).maxX
        let rowStart = root.convert(NSPoint(x: SidebarMetrics.sideInset, y: 0), to: nil).x
        let fitted = max(SidebarMetrics.trafficLightClearance, ceil(lightsEnd - rowStart + SidebarMetrics.trafficLightGap))
        if constraint.constant != fitted { constraint.constant = fitted }
    }

    private func rebuildEntries(_ state: BrowserState, pinsAnimation: PinsAnimation?) {
        let workspace = state.currentWorkspace
        pageControls.removeAll()
        folderControls.removeAll()
        dropSlotViews.removeAll()
        hoverCard.dismiss()
        entries.accent = accent
        let existingIDs = Set(state.profiles.flatMap { $0.favorites.map(\.id) } +
                              state.workspaces.flatMap { ($0.pins + $0.tabs).map(\.id) })
        pageIcons = pageIcons.filter { existingIDs.contains($0.key) }
        for view in entries.arrangedSubviews {
            entries.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let rows = state.sidebarRows()
        addSection("Favorites", rows: rows[.favorites] ?? [])
        let spaceHeader = makeSpaceHeader(workspace, animatingFromCollapsed: pinsAnimation.map { !$0.expanding })
        entries.addArrangedSubview(spaceHeader)
        spaceHeaderRow = spaceHeader
        spaceHeader.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
        if workspace.pinsCollapsed { entries.setCustomSpacing(SidebarMetrics.collapsedPinsGap, after: spaceHeader) }
        let pinnedStart = entries.arrangedSubviews.count
        pinnedViews = []
        if !workspace.pinsCollapsed {
            addSection("Pinned", rows: rows[.pinned(folder: nil)] ?? [], includeEmpty: !workspace.folders.isEmpty)
            for folder in workspace.subfolders(of: nil) { addFolder(folder, depth: 1, workspace: workspace, rows: rows) }
        }
        pinnedViews = Array(entries.arrangedSubviews[pinnedStart...])
        let belowStart = entries.arrangedSubviews.count
        addSection("Tabs", rows: rows[.tabs] ?? [])
        if let pinsAnimation {
            animatePinnedSection(pinsAnimation, pinned: pinnedStart..<belowStart, below: belowStart..<entries.arrangedSubviews.count)
        }
        entries.restoreFavoritesZone()
    }

    private func render() {
        defer { onSpacesChanged?() }
        // A rebuild would drop the clipped picture mid-animation; the latest state is drawn when it ends.
        guard !pinsAnimating else { renderDeferred = true; return }
        fitTrafficLightClearance()
        commandBar?.refresh()
        settingsWindow?.reload()
        let state = runtime.state
        let workspace = state.currentWorkspace
        if slide == nil { (root as? WorkspaceRoot)?.theme = theme }
        for frame in cardFrames.allObjects {
            frame.theme = theme
            frame.showsEmptyState = state.showsEmptySpace
            frame.canAddSplit = runtime.supportsSplits && state.canSplitSelection
            frame.focusedPane = focusedPaneIndex
        }
        paneOverlays.allObjects.forEach { $0.refresh() }
        let currentProfile = state.profiles.first(where: { $0.id == workspace.profileID })
        switcherButton.title = workspace.name
        switcherButton.image = colorDot(workspaceColor(workspace.color))
        switcherButton.toolTip = "\(workspace.name) · Profile \(currentProfile?.name ?? "")"
        switcherButton.setAccessibilityValue("\(workspace.name), Profile \(currentProfile?.name ?? "")")
        let focusedControl = pageControls.first { _, controls in
            root.window?.firstResponder === controls.select || root.window?.firstResponder === controls.close
        }.map { (id: $0.key, close: root.window?.firstResponder === $0.value.close) }
        let focusedFolder = folderControls.compactMap { id, controls -> (id: UUID, role: Int)? in
            let ordered = [controls.disclosure, controls.title, controls.actions]
            guard let role = ordered.firstIndex(where: { root.window?.firstResponder === $0 }) else { return nil }
            return (id, role)
        }.first
        let parentOfFocusedPin = focusedControl.flatMap { workspace.folder(containingPin: $0.id)?.id }
        let pinsAnimation = pendingPinsAnimation
        pendingPinsAnimation = nil
        rebuildEntries(state, pinsAnimation: pinsAnimation)
        if let focusedControl, let controls = pageControls[focusedControl.id] {
            root.window?.makeFirstResponder(focusedControl.close ? controls.close : controls.select)
        } else if let focusedFolder, let controls = folderControls[focusedFolder.id] {
            let ordered = [controls.disclosure, controls.title, controls.actions]
            root.window?.makeFirstResponder(ordered[focusedFolder.role])
        } else if let parentOfFocusedPin, let controls = folderControls[parentOfFocusedPin] {
            root.window?.makeFirstResponder(controls.disclosure)
        }
        workspacePager.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in state.workspaces {
            let isActive = item.id == state.activeWorkspaceID
            let dot = ActionButton(title: "") { [weak self] in self?.switchWorkspace(item.id) }
            dot.image = pagerDot(isActive: isActive)
            dot.imagePosition = .imageOnly
            dot.isBordered = false
            dot.focusRingType = .none
            dot.setAccessibilityLabel(item.name)
            dot.setAccessibilityValue(isActive ? "current" : nil)
            dot.toolTip = item.name
            dot.acceptsEntryDrops { [weak self] id in self?.dropEntry(id, onWorkspace: item.id) ?? false }
            dot.widthAnchor.constraint(equalToConstant: 14).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 24).isActive = true
            workspacePager.addArrangedSubview(dot)
        }
        profileButton.title = currentProfile?.name ?? ""
        profileButton.image = currentProfile.map { colorDot(workspaceColor(state.displayColor(of: $0))) }
        profileButton.toolTip = "Profile: \(currentProfile?.name ?? "")"
        profileButton.setAccessibilityValue(currentProfile?.name ?? "")
        downloadsSidebar?.setProfileKey(downloadsProfileKey(workspace.profileID))
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
        case .peekAlreadyOpen:
            statusLabel.stringValue = "A Peek is already open. Close it or open it as a tab first."
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

    private func pageTitle(_ page: PageEntry) -> String {
        page.title.isEmpty ? (page.lastURL.host ?? "Page") : page.title
    }

    private func addSection(_ title: String, rows pages: [SidebarRow], includeEmpty: Bool = false) {
        // Shared Favorites deserve space when present, without three empty
        // diagnostic sections competing with a new workspace's first tab.
        guard !pages.isEmpty || title == "Tabs" || includeEmpty else { return }
        if title == "Tabs", !entries.arrangedSubviews.isEmpty {
            let divider = NSBox()
            divider.boxType = .separator
            entries.addArrangedSubview(divider)
            divider.widthAnchor.constraint(equalTo: entries.widthAnchor, constant: -8).isActive = true
        }
        if title == "Tabs" {
            let tidyClear = makeTidyClearRow()
            entries.addArrangedSubview(tidyClear)
            tidyClear.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
            entries.addArrangedSubview(newTabRow)
            dropSlotViews.append((newTabRow, .newTabRow))
            newTabRow.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
        }
        if pages.isEmpty && title == "Tabs" {
            let empty = NSTextField(wrappingLabelWithString: "No tabs yet.\nOpen a website to start browsing.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.setAccessibilityIdentifier("bato-empty-tabs")
            entries.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: entries.widthAnchor, constant: -12).isActive = true
        }
        if title == "Favorites" {
            for start in stride(from: 0, to: pages.count, by: SidebarStyle.tilesPerRow) {
                let row = NSStackView()
                row.orientation = .horizontal
                row.distribution = .fillEqually
                row.spacing = 4
                for (offset, favorite) in pages[start..<min(start + SidebarStyle.tilesPerRow, pages.count)].enumerated() {
                    guard case .page(let page) = favorite.content else { continue }
                    let tile = makePageView(page, tile: true)
                    row.addArrangedSubview(tile)
                    dropSlotViews.append((tile, .tile(index: start + offset)))
                }
                while row.arrangedSubviews.count < SidebarStyle.tilesPerRow { row.addArrangedSubview(NSView()) }
                entries.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
            }
        } else {
            for (index, entry) in pages.enumerated() {
                let row = makeRowView(entry)
                dropSlotViews.append((row, .row(section: title == "Tabs" ? .tabs : .pinned(folder: nil), index: index)))
                entries.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
            }
        }
        if let last = entries.arrangedSubviews.last { entries.setCustomSpacing(12, after: last) }
    }

    private func makeRowView(_ row: SidebarRow) -> NSView {
        switch row.content {
        case .page(let page): return makePageView(page, tile: false)
        case .pair(let split, let left, let right): return makePairView(split, left: left, right: right)
        }
    }

    private func makePageView(_ page: PageEntry, tile: Bool) -> NSView {
        let title = page.title.isEmpty ? (page.lastURL.host ?? "Page") : page.title
        let select = ActionButton(title: title) { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.selectEntry(page.id) }
        }
        select.isBordered = false
        select.bezelStyle = .recessed
        select.focusRingType = .none
        select.alignment = tile ? .center : .left
        select.font = SidebarStyle.rowFont
        let iconSize = tile ? SidebarStyle.tileIconSize : SidebarStyle.rowIconSize
        if let icon = pageIcons[page.id]?.copy() as? NSImage {
            icon.size = NSSize(width: iconSize, height: iconSize)
            select.image = icon
            select.imageScaling = .scaleProportionallyDown
        } else {
            select.image = SidebarStyle.letterIcon(for: title, url: page.lastURL, size: iconSize)
        }
        select.imagePosition = tile ? .imageOnly : .imageLeading
        select.imageHugsTitle = true
        select.setButtonType(.momentaryPushIn)
        select.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        select.setContentHuggingPriority(.defaultLow, for: .horizontal)
        (select.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        select.setAccessibilityIdentifier("bato-page-\(page.id.uuidString)")
        select.setAccessibilityLabel(title)
        select.setAccessibilityHelp(page.lastURL.absoluteString)
        configurePageMenu(select, page: page)
        let close = ActionButton(title: "") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.closeEntry(page.id) }
        }
        close.image = sidebarSymbol("xmark", size: 9)
        close.imagePosition = .imageOnly
        close.isBordered = false
        close.bezelStyle = .recessed
        close.focusRingType = .none
        close.contentTintColor = .secondaryLabelColor
        close.setAccessibilityLabel(page.kind == .temporary ? "Close \(title)" : "Unload \(title)")
        close.setAccessibilityIdentifier("bato-close-\(page.id.uuidString)")
        close.toolTip = page.kind == .temporary ? "Close tab" : "Unload saved page"
        close.isEnabled = !runtime.pendingClose.contains(where: { $0.entryID == page.id })
        // Small borderless close controls stay present for keyboard and AX access;
        // hover changes the surface, never the set of available actions.
        let row = SidebarPageView(select: select, close: close, tile: tile,
                                  selected: sidebarState.currentWorkspace.activeEntryID == page.id,
                                  accent: accent)
        pageControls[page.id] = (select, close)
        let card = SidebarHoverCardContent(title: page.title, url: page.lastURL)
        row.hoverChanged = { [weak self, weak row] inside in
            guard let self, let row else { return }
            guard inside, self.hasStarted, self.root.window?.attachedSheet == nil else { return self.hoverCard.dismiss() }
            self.hoverCard.schedule(card, anchor: row)
        }
        select.beginDrag = { [weak self, weak row] event in
            guard let self, let row, self.runtime.state.visibleEntries.contains(where: { $0.id == page.id }) else { return }
            self.hoverCard.dismiss()
            let noFavorites = self.runtime.state.profiles.first { $0.id == self.runtime.state.currentWorkspace.profileID }?.favorites.isEmpty ?? false
            self.entries.setFavoritesZone(visible: noFavorites && self.runtime.state.canPlaceEntry(page.id, in: .favorites))
            self.entryDragSource.begin(entryID: page.id, row: row, event: event)
        }
        TabAudioBadge.attach(to: row, entryID: page.id, tile: tile, select: select)
        return row
    }

    /// One pill split into two halves, each with its own favicon, title and close; the pair is one row of the list.
    private func makePairView(_ split: PageSplit, left: PageEntry, right: PageEntry) -> NSView {
        let workspaceID = sidebarState.activeWorkspaceID
        let isDisplayed = sidebarState.currentSplit?.id == split.id
        let activeID = sidebarState.currentWorkspace.activeEntryID
        let halves = [left, right].enumerated().map { index, page -> SidebarPairHalf in
            let title = pageTitle(page)
            let isClosing = runtime.pendingClose.contains { $0.entryID == page.id }
            let select = ActionButton(title: title) { [weak self] in
                guard let self, self.canRunSplitAction(in: workspaceID),
                      self.runtime.state.currentWorkspace.splits.contains(where: { $0.id == split.id }) else { return }
                self.perform { self.runtime.activateSplit(split.id, focusedEntryID: page.id) }
            }
            select.isBordered = false
            select.bezelStyle = .recessed
            select.focusRingType = .none
            select.alignment = .left
            select.font = SidebarStyle.rowFont
            let iconSize = SidebarStyle.rowIconSize
            if let icon = pageIcons[page.id]?.copy() as? NSImage {
                icon.size = NSSize(width: iconSize, height: iconSize)
                select.image = icon
                select.imageScaling = .scaleProportionallyDown
            } else {
                select.image = SidebarStyle.letterIcon(for: title, url: page.lastURL, size: iconSize)
            }
            select.imagePosition = .imageLeading
            select.imageHugsTitle = true
            select.setButtonType(.momentaryPushIn)
            select.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            select.setContentHuggingPriority(.defaultLow, for: .horizontal)
            (select.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            let position = split.orientation == .horizontal ? (index == 0 ? "left" : "right") : (index == 0 ? "top" : "bottom")
            select.setAccessibilityIdentifier("bato-split-\(position)-\(split.id.uuidString)")
            select.setAccessibilityLabel("Focus \(position) page: \(title)")
            select.setAccessibilityHelp(page.lastURL.absoluteString)
            select.isEnabled = !isClosing
            let close = ActionButton(title: "") { [weak self] in
                guard let self else { return }
                self.perform { self.runtime.closeEntry(page.id) }
            }
            close.image = sidebarSymbol("xmark", size: 9)
            close.imagePosition = .imageOnly
            close.isBordered = false
            close.bezelStyle = .recessed
            close.focusRingType = .none
            close.contentTintColor = .secondaryLabelColor
            close.setAccessibilityLabel("Close \(title)")
            close.setAccessibilityIdentifier("bato-close-\(page.id.uuidString)")
            close.toolTip = page.kind == .temporary ? "Close tab" : "Unload saved page"
            close.isEnabled = !isClosing
            pageControls[page.id] = (select, close)
            return SidebarPairHalf(select: select, close: close, card: SidebarHoverCardContent(title: page.title, url: page.lastURL),
                                   isFocused: activeID == page.id)
        }
        let pairClose = ActionButton(title: "") { [weak self] in
            guard let self else { return }
            self.perform {
                let closedLeft = self.runtime.closeEntry(split.leftEntryID)
                let closedRight = self.runtime.closeEntry(split.rightEntryID)
                return closedLeft || closedRight
            }
        }
        pairClose.image = sidebarSymbol("xmark", size: 9)
        pairClose.imagePosition = .imageOnly
        pairClose.isBordered = false
        pairClose.bezelStyle = .recessed
        pairClose.focusRingType = .none
        pairClose.contentTintColor = .secondaryLabelColor
        pairClose.toolTip = "Close both tabs"
        pairClose.setAccessibilityLabel("Close both tabs")
        pairClose.setAccessibilityIdentifier("bato-close-split-\(split.id.uuidString)")
        let row = SidebarPairView(halves: halves, pairClose: pairClose, selected: isDisplayed, accent: accent)
        row.setAccessibilityIdentifier("bato-split-row-\(split.id.uuidString)")
        row.hoverChanged = { [weak self, weak row] half in
            guard let self, let row else { return }
            guard let half, self.hasStarted, self.root.window?.attachedSheet == nil else { return self.hoverCard.dismiss() }
            self.hoverCard.schedule(halves[half].card, anchor: row.halfView(half))
        }
        let menu = pairMenu(split, workspaceID: workspaceID)
        row.menu = menu
        for half in halves {
            half.select.menu = menu
            half.select.beginDrag = { [weak self, weak row] event in
                guard let self, let row, self.runtime.state.currentWorkspace.splits.contains(where: { $0.id == split.id }) else { return }
                self.hoverCard.dismiss()
                self.entries.setFavoritesZone(visible: false)
                self.entryDragSource.begin(entryID: split.leftEntryID, row: row, event: event)
            }
        }
        return row
    }

    private func pairMenu(_ split: PageSplit, workspaceID: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let state = runtime.state
        let isClosing = runtime.pendingClose.contains { split.contains($0.entryID) }
        let canAct = runtime.supportsSplits && !isClosing
        let splitID = split.id
        let current = state.currentWorkspace
        func item(_ title: String, enabled: Bool = true, _ action: @escaping () -> Bool) -> ActionMenuItem {
            let item = ActionMenuItem(title: title) { [weak self] in
                guard let self, self.canRunSplitAction(in: workspaceID),
                      self.runtime.state.currentWorkspace.splits.contains(where: { $0.id == splitID }) else { return }
                self.perform(action)
            }
            item.isEnabled = enabled && canAct
            return item
        }
        if !split.isPinned {
            let pin = item("Pin Pair") { [weak self] in self?.runtime.pinSplit(splitID) ?? false }
            pin.toolTip = "Save both destinations as a pinned pair."
            menu.addItem(pin)
        }
        let separate = item("Separate All Tabs") { [weak self] in self?.runtime.dissolveSplit(splitID) ?? false }
        separate.toolTip = "Both pages remain available as separate rows."
        menu.addItem(separate)
        menu.addItem(.separator())
        menu.addItem(item("Swap Sides") { [weak self] in self?.runtime.swapSplitSides(splitID) ?? false })
        let toVertical = split.orientation == .horizontal
        menu.addItem(item(toVertical ? "Convert to Vertical Split View" : "Convert to Horizontal Split View") { [weak self] in
            self?.runtime.setSplitOrientation(splitID, to: toVertical ? .vertical : .horizontal) ?? false
        })
        let displayed = state.currentSplit?.id == splitID
        let widths = NSMenuItem(title: "Adjust Widths", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (title, adjustment) in [("Widen First Page", 0.1), ("Equal Size", 0.0), ("Widen Second Page", -0.1)] {
            let target = adjustment == 0 ? 0.5 : min(0.9, max(0.1, split.dividerRatio + adjustment))
            submenu.addItem(item(title, enabled: displayed && abs(target - split.dividerRatio) > 0.0001) { [weak self] in
                self?.runtime.updateSplitRatio(splitID, ratio: target) ?? false
            })
        }
        widths.submenu = submenu
        widths.isEnabled = displayed && canAct
        menu.addItem(widths)
        menu.addItem(.separator())
        for entryID in [split.leftEntryID, split.rightEntryID] {
            guard let page = (state.currentWorkspace.pins + state.currentWorkspace.tabs).first(where: { $0.id == entryID }) else { continue }
            let tabItem = NSMenuItem(title: pageTitle(page), action: nil, keyEquivalent: "")
            tabItem.image = pageIcons[entryID].flatMap { ($0.copy() as? NSImage) }.map { icon in icon.size = NSSize(width: 14, height: 14); return icon }
            let tabMenu = NSMenu()
            tabMenu.autoenablesItems = false
            tabMenu.addItem(item("Separate from Split View") { [weak self] in self?.runtime.dissolveSplit(splitID) ?? false })
            tabMenu.addItem(.separator())
            let copyItem = ActionMenuItem(title: "Copy Link") { [weak self] in
                self?.copyLink(entryID: entryID, workspaceID: workspaceID, profileID: current.profileID)
            }
            copyItem.isEnabled = canAct
            tabMenu.addItem(copyItem)
            tabMenu.addItem(.separator())
            tabMenu.addItem(item("Close Tab") { [weak self] in self?.runtime.closeEntry(entryID) ?? false })
            tabItem.submenu = tabMenu
            menu.addItem(tabItem)
        }
        menu.addItem(.separator())
        let transfer = NSMenuItem(title: "Move to Workspace", action: nil, keyEquivalent: "")
        let destinations = NSMenu()
        destinations.autoenablesItems = false
        for destination in state.workspaces where destination.id != current.id && destination.profileID == current.profileID {
            let destinationID = destination.id
            destinations.addItem(item(destination.name, enabled: state.canMoveSplit(splitID, toWorkspace: destinationID)) { [weak self] in
                self?.runtime.moveSplit(splitID, toWorkspace: destinationID) ?? false
            })
        }
        transfer.submenu = destinations
        transfer.isEnabled = destinations.items.contains(where: \.isEnabled)
        menu.addItem(transfer)
        menu.addItem(.separator())
        menu.addItem(item("Close Both Tabs") { [weak self] in
            guard let self else { return false }
            if split.isPinned { return self.runtime.closePinnedPair(split.id) }
            let closedLeft = self.runtime.closeEntry(split.leftEntryID)
            let closedRight = self.runtime.closeEntry(split.rightEntryID)
            return closedLeft || closedRight
        })
        return menu
    }

    private func configurePageMenu(_ select: NSButton, page: PageEntry) {
        if page.kind == .temporary {
            let menu = PageMenu()
            menu.addItem(ActionMenuItem(title: "Pin Tab") { [weak self] in
                guard let self else { return }
                self.perform { self.runtime.pinEntry(page.id) }
            })
            menu.addItem(ActionMenuItem(title: "Add to Favorites") { [weak self] in
                guard let self else { return }
                self.perform { self.runtime.favoriteEntry(page.id) }
            })
            menu.addItem(ActionMenuItem(title: "Archive Tab") { [weak self] in
                guard let self else { return }
                self.perform { self.runtime.archiveTab(page.id) }
            })
            select.menu = menu
        } else {
            let menu = PageMenu()
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
            addBasicItems(to: menu, page: page)
            let workspaceID = runtime.state.activeWorkspaceID
            let profileID = runtime.state.currentWorkspace.profileID
            let entryID = page.id
            let copy = ActionMenuItem(title: "Copy URL") { [weak self] in
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
                let canSplit = runtime.state.canCreateSplit(with: page.id) &&
                    !runtime.pendingClose.contains(where: { $0.entryID == page.id || $0.entryID == sourceID })
                let split = NSMenuItem(title: "Open in Split View", action: nil, keyEquivalent: "")
                split.image = sidebarSymbol("rectangle.split.2x1", size: 13)
                let sides = NSMenu()
                sides.autoenablesItems = false
                for side in [SplitSide.right, .left, .top, .bottom] {
                    let item = ActionMenuItem(title: side.title.replacingOccurrences(of: "Add ", with: "").replacingOccurrences(of: " Split", with: "")) { [weak self] in
                        guard let self, self.canRunSplitAction(in: workspaceID),
                              self.runtime.state.currentWorkspace.activeEntryID == sourceID,
                              self.runtime.state.canCreateSplit(with: page.id) else { return }
                        self.perform { self.runtime.createSplit(with: page.id, side: side) }
                    }
                    item.image = sidebarSymbol(side.symbolName, size: 13)
                    item.isEnabled = canSplit
                    sides.addItem(item)
                }
                split.submenu = sides
                split.isEnabled = canSplit
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

    /// Close, Duplicate, Reload and Open in Peek lead every tab's menu. Reload and Peek act on
    /// the page the engine is showing, so they are enabled only for the selected page.
    private func addBasicItems(to menu: NSMenu, page: PageEntry) {
        let isClosing = runtime.pendingClose.contains(where: { $0.entryID == page.id })
        let isSelected = runtime.state.currentWorkspace.activeEntryID == page.id
        let close = ActionMenuItem(title: "Close Tab") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.closeEntry(page.id) }
        }
        close.isEnabled = !isClosing
        let duplicate = ActionMenuItem(title: "Duplicate") { [weak self] in
            guard let self else { return }
            self.perform { self.runtime.addTab(url: page.lastURL, title: page.title) }
        }
        duplicate.isEnabled = !isClosing
        let reload = ActionMenuItem(title: "Reload") { [weak self] in
            guard let self, self.runtime.state.currentWorkspace.activeEntryID == page.id else { return }
            self.perform { self.runtime.perform(.load(page.lastURL)) }
        }
        reload.isEnabled = isSelected && !isClosing && runtime.canPerform(.load(page.lastURL))
        let peek = ActionMenuItem(title: "Open in Peek") { [weak self] in
            guard let self, let live = self.runtime.livePages[page.id] else { return }
            self.perform { self.runtime.openPeek(from: live, url: page.lastURL) }
        }
        peek.isEnabled = isSelected && runtime.livePages[page.id].map {
            runtime.canOpenPeek(from: $0, url: page.lastURL)
        } == true
        menu.addItem(.separator())
        [close, duplicate, reload, peek].forEach(menu.addItem)
        if let menu = menu as? PageMenu { menu.add(muteItemFor: page.id) }
        menu.addItem(.separator())
    }

    @discardableResult
    private func copyLink(entryID: UUID, workspaceID: UUID, profileID: UUID, format: LinkFormat = .url) -> Bool {
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
        pasteboard.setString(format.text(title: entry.title, url: entry.lastURL), forType: .string)
        CopiedToast.show(in: window)
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

    private func addFolder(_ folder: PageFolder, depth: Int, workspace: Workspace, rows: [BrowserState.SidebarSection: [SidebarRow]]) {
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
        title.image = folderGlyph(collapsed: folder.isCollapsed)
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
        dropSlotViews.append((heading, .folder(id: folderID, pinCount: pinCount)))
        title.menu = folderMenu(folderID, workspaceID: workspaceID)
        if !folder.isCollapsed {
            for (index, entry) in (rows[.pinned(folder: folderID)] ?? []).enumerated() {
                let row = makeRowView(entry)
                dropSlotViews.append((row, .row(section: .pinned(folder: folderID), index: index)))
                addIndented(row, leading: 14 + indent)
            }
            for child in workspace.subfolders(of: folderID) {
                addFolder(child, depth: depth + 1, workspace: workspace, rows: rows)
            }
        }
        if depth == 1, let last = entries.arrangedSubviews.last { entries.setCustomSpacing(9, after: last) }
    }

    /// Palette-rendered so only the glyph takes the workspace colour; the button tint would also recolour the name.
    private func folderGlyph(collapsed: Bool) -> NSImage {
        let symbol = sidebarSymbol(collapsed ? "folder.fill" : "folder", size: 13)
        let tinted = symbol.withSymbolConfiguration(.init(paletteColors: [SidebarStyle.vivid(accent)])) ?? symbol
        tinted.isTemplate = false
        return tinted
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

    private func resolveDrop(entryID: UUID, at point: NSPoint) -> SidebarDropTarget? {
        guard hasStarted, canDrag(entryID) else { return nil }
        let workspace = runtime.state.currentWorkspace
        let filed = Set(workspace.folders.flatMap(\.pinIDs))
        let slots = dropSlotViews.compactMap { slot -> SidebarDropSlot? in
            guard slot.view.window != nil else { return nil }
            return SidebarDropSlot(kind: slot.kind, frame: entries.convert(slot.view.bounds, from: slot.view))
        }
        guard let target = SidebarDropMap.resolve(point: point, slots: (entries.favoritesZoneSlot.map { [$0] } ?? []) + slots,
                                                  unfiledPinCount: workspace.pins.filter { !filed.contains($0.id) }.count),
              canPlace(entryID, in: target.section) else { return nil }
        return target
    }

    /// A drag carries one entry id; the left member of a pair stands for the whole pair.
    private func canDrag(_ entryID: UUID) -> Bool {
        runtime.state.split(containingEntry: entryID) != nil || runtime.state.canPlaceEntry(entryID, in: .tabs)
    }

    private func canPlace(_ entryID: UUID, in section: BrowserState.SidebarSection) -> Bool {
        if let split = runtime.state.split(containingEntry: entryID) { return runtime.state.canPlaceSplit(split.id, in: section) }
        return runtime.state.canPlaceEntry(entryID, in: section)
    }

    private func performDrop(entryID: UUID, target: SidebarDropTarget) -> Bool {
        guard hasStarted else { return false }
        let placed = runtime.state.split(containingEntry: entryID).map { runtime.placeSplit($0.id, in: target.section, at: target.index) }
            ?? runtime.placeEntry(entryID, in: target.section, at: target.index)
        render()
        return placed
    }

    private func dropEntry(_ entryID: UUID, onWorkspace destinationID: UUID) -> Bool {
        let state = runtime.state
        let split = state.split(containingEntry: entryID)
        guard hasStarted, split.map({ state.canMoveSplit($0.id, toWorkspace: destinationID) })
                ?? state.canMoveEntry(entryID, toWorkspace: destinationID) else { return false }
        let moved = split.map { runtime.moveSplit($0.id, toWorkspace: destinationID) }
            ?? runtime.moveEntry(entryID, toWorkspace: destinationID)
        render()
        return moved
    }

    private func perform(_ command: () -> Bool) {
        guard hasStarted else { return }
        _ = command()
        render()
    }

    private struct PinsAnimation {
        let expanding: Bool
        /// What the pinned section looked like before it collapsed.
        let snapshot: PinsSnapshot?
    }

    /// A picture of the pinned section. `fullHeight` is the space it takes between the Space header and the next row.
    private struct PinsSnapshot {
        let image: NSImage
        let offsetY: CGFloat
        let fullHeight: CGFloat
        let size: NSSize
    }

    private func makeSpaceHeader(_ workspace: Workspace, animatingFromCollapsed: Bool?) -> SpaceHeaderRow {
        let workspaceID = workspace.id
        let header = SpaceHeaderRow(name: workspace.name, color: workspaceColor(workspace.color), icon: workspace.icon,
                                    collapsed: animatingFromCollapsed ?? workspace.pinsCollapsed)
        header.toggle = { [weak self] in self?.togglePins(inWorkspace: workspaceID) }
        header.showActions = { [weak self, weak header] in
            guard let self, let header else { return }
            self.showSpaceActions(workspaceID, anchor: header.actionsAnchor)
        }
        header.hoverChanged = { [weak self] _ in self?.hoverCard.dismiss() }
        if animatingFromCollapsed != nil {
            DispatchQueue.main.async { header.setCollapsed(workspace.pinsCollapsed, animated: !Self.reducesMotion) }
        }
        return header
    }

    private static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func togglePins(inWorkspace id: UUID) {
        guard hasStarted, runtime.state.activeWorkspaceID == id, root.window?.attachedSheet == nil else { return }
        let collapsed = runtime.state.currentWorkspace.pinsCollapsed
        pendingPinsAnimation = PinsAnimation(expanding: collapsed, snapshot: collapsed ? nil : snapshotOfPinnedSection())
        perform { runtime.setPinsCollapsed(!collapsed, inWorkspace: id) }
        pendingPinsAnimation = nil
    }

    private func snapshotOfPinnedSection() -> PinsSnapshot? {
        let views = pinnedViews.filter { $0.superview === entries }
        guard let last = views.last, let next = entries.arrangedSubviews.firstIndex(of: last).map({ $0 + 1 }),
              next < entries.arrangedSubviews.count else { return nil }
        return snapshot(of: views, next: entries.arrangedSubviews[next])
    }

    private func snapshot(of views: [NSView], next: NSView) -> PinsSnapshot? {
        guard let header = spaceHeaderRow, let first = views.first else { return nil }
        let frame = views.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        guard let rep = entries.bitmapImageRepForCachingDisplay(in: frame) else { return nil }
        entries.cacheDisplay(in: frame, to: rep)
        let image = NSImage(size: frame.size)
        image.addRepresentation(rep)
        return PinsSnapshot(image: image, offsetY: frame.minY - header.frame.maxY,
                            fullHeight: next.frame.minY - header.frame.maxY, size: frame.size)
    }

    /// Between the header and the content below sits a clipped picture of the pinned rows whose height animates, so the
    /// content follows it in lockstep and the rows never overlap it: collapsing wipes the picture out, expanding wipes it in.
    private func animatePinnedSection(_ animation: PinsAnimation, pinned: Range<Int>, below: Range<Int>) {
        guard !Self.reducesMotion, let header = spaceHeaderRow else { return }
        entries.layoutSubtreeIfNeeded()
        let views = entries.arrangedSubviews
        let hidden = animation.expanding ? Array(views[pinned]) : []
        let picture: PinsSnapshot?
        if animation.expanding {
            picture = views.indices.contains(below.lowerBound) ? snapshot(of: hidden, next: views[below.lowerBound]) : nil
        } else {
            picture = animation.snapshot
        }
        guard let picture else { return }
        let collapsedHeight = SidebarMetrics.collapsedPinsGap
        let box = PinnedClipView(image: picture.image, offsetY: picture.offsetY, size: picture.size)
        let height = box.heightAnchor.constraint(equalToConstant: animation.expanding ? collapsedHeight : picture.fullHeight)
        height.isActive = true
        entries.insertArrangedSubview(box, at: pinned.lowerBound)
        box.widthAnchor.constraint(equalTo: entries.widthAnchor).isActive = true
        entries.setCustomSpacing(0, after: header)
        entries.setCustomSpacing(0, after: box)
        hidden.forEach { $0.isHidden = true }
        box.picture.alphaValue = animation.expanding ? 0 : 1
        let collapsing = !animation.expanding
        pinsAnimating = true
        let startHeight = height.constant
        let endHeight = collapsing ? collapsedHeight : picture.fullHeight
        let started = CACurrentMediaTime()
        let finish: () -> Void = { [weak self, weak header, weak box] in
            guard let self else { return }
            self.pinsAnimating = false
            box?.removeFromSuperview()
            hidden.forEach { $0.isHidden = false }
            if let header, header.superview === self.entries {
                if collapsing { self.entries.setCustomSpacing(collapsedHeight, after: header) } else { self.entries.setCustomSpacing(NSStackView.useDefaultSpacing, after: header) }
            }
            self.newTabRow.refreshHover()
            if self.renderDeferred {
                self.renderDeferred = false
                self.render()
            }
        }
        // Stepped by hand: the stack must relayout every frame so the rows below follow the box exactly.
        nonisolated(unsafe) var ticker: Timer?
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let progress = min(1, (CACurrentMediaTime() - started) / SidebarMetrics.pinsAnimationDuration)
                let eased = 1 - pow(1 - progress, 3)
                height.constant = startHeight + (endHeight - startHeight) * eased
                box.picture.alphaValue = collapsing ? 1 - eased : eased
                if progress >= 1 {
                    ticker?.invalidate()
                    finish()
                }
            }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func showSpaceActions(_ id: UUID, anchor: NSView) {
        guard hasStarted, workspaceEditor == nil, folderEditor == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil, runtime.state.activeWorkspaceID == id else { return }
        requestNativeFocus?()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: "Rename Space…") { [weak self] in self?.editWorkspace() })
        menu.addItem(ActionMenuItem(title: "Edit Theme…") { [weak self] in self?.editTheme() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "New Folder…") { [weak self] in
            guard let self, self.runtime.state.activeWorkspaceID == id else { return }
            self.editFolder()
        })
        let collapsed = runtime.state.currentWorkspace.pinsCollapsed
        menu.addItem(ActionMenuItem(title: collapsed ? "Show Pinned" : "Hide Pinned") { [weak self] in self?.togglePins(inWorkspace: id) })
        menu.addItem(.separator())
        let delete = ActionMenuItem(title: "Delete Space…") { [weak self] in self?.confirmDeleteWorkspace(id) }
        delete.isEnabled = runtime.state.canDeleteWorkspace(id)
        menu.addItem(delete)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY + 2), in: anchor)
    }

    private func makeTidyClearRow() -> TidyClearRow {
        let state = runtime.state
        let row = TidyClearRow(canTidy: !state.duplicateTabIDs().isEmpty, canClear: !state.clearableTabIDs().isEmpty)
        row.alphaValue = pointerInSidebar ? 1 : 0
        row.tidy = { [weak self] in
            guard let self, self.hasStarted else { return }
            self.perform { self.runtime.archiveTabs(self.runtime.state.duplicateTabIDs()) > 0 }
        }
        row.clear = { [weak self] in
            guard let self, self.hasStarted else { return }
            self.perform { self.runtime.archiveTabs(self.runtime.state.clearableTabIDs()) > 0 }
        }
        tidyClearRow = row
        return row
    }

    private func setPointerInSidebar(_ inside: Bool) {
        pointerInSidebar = inside
        guard let row = tidyClearRow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            row.animator().alphaValue = inside ? 1 : 0
        }
    }

    @objc private func showWorkspaceActions() {
        guard hasStarted, workspaceEditor == nil, folderEditor == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let id = runtime.state.activeWorkspaceID
        requestNativeFocus?()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: "Edit Workspace…") { [weak self] in self?.editWorkspace() })
        menu.addItem(.separator())
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
        menu.addItem(.separator())
        let delete = ActionMenuItem(title: "Delete Workspace…") { [weak self] in self?.confirmDeleteWorkspace(id) }
        delete.isEnabled = runtime.state.canDeleteWorkspace(id)
        menu.addItem(delete)
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

    /// Shows the Create a Space page in place of the sidebar list. The draft theme previews on the window; Cancel
    /// leaves organization untouched.
    private func createSpace() {
        guard hasStarted, createSpacePage == nil, workspaceEditor == nil, folderEditor == nil, profileEditor == nil,
              themePopover == nil, let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        finishSlideNow()
        let state = runtime.state
        let profileID = state.currentWorkspace.profileID
        let color = state.nextWorkspaceColor(in: sidebarColorPalette.map(\.hex), profileID: profileID)
        var draft = SpaceTheme(color: color)
        draft.intensity = Self.newSpaceIntensity
        let profileName = state.profiles.first { $0.id == profileID }?.name ?? "Default"
        let page = CreateSpacePageView(theme: draft, profileName: profileName)
        page.onThemeChange = { [weak self] in self?.previewTheme($0) }
        page.onCancel = { [weak self] in self?.dismissCreateSpacePage() }
        page.onCreate = { [weak self] name, icon, theme in
            guard let self else { return }
            guard self.runtime.state.currentWorkspace.profileID == profileID else { return self.dismissCreateSpacePage() }
            let before = self.runtime.state.workspaces.count
            _ = self.runtime.addWorkspace(name: name, theme: theme, icon: icon)
            guard self.runtime.state.workspaces.count > before else { return NSSound.beep() }
            self.dismissCreateSpacePage()
        }
        page.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: sidebarScroll.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            page.topAnchor.constraint(equalTo: sidebarScroll.topAnchor),
            page.bottomAnchor.constraint(equalTo: sidebarScroll.bottomAnchor)
        ])
        createSpacePage = page
        sidebarScroll.alphaValue = 0
        requestNativeFocus?()
        previewTheme(draft)
        if !Self.reducesMotion { slideIn(page) }
        page.focusName()
    }

    private static let newSpaceIntensity = 0.6

    private func slideIn(_ page: NSView) {
        page.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = sidebarScroll.bounds.width
        animation.toValue = 0
        animation.duration = 0.24
        animation.timingFunction = SpaceSlide.releaseTiming
        page.layer?.add(animation, forKey: "slideIn")
    }

    private func dismissCreateSpacePage() {
        guard let page = createSpacePage else { return }
        createSpacePage = nil
        themePreview = nil
        sidebarScroll.alphaValue = 1
        page.removeFromSuperview()
        render()
    }

    private func previewTheme(_ draft: SpaceTheme) {
        themePreview = draft
        (root as? WorkspaceRoot)?.theme = draft
        for frame in cardFrames.allObjects { frame.theme = draft }
    }

    /// Edits the current Space's theme in the same popover the Create page uses; the change previews live and is
    /// saved when the popover closes.
    private func editTheme() {
        guard hasStarted, createSpacePage == nil, themePopover == nil, workspaceEditor == nil, folderEditor == nil,
              let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil,
              let anchor = spaceHeaderRow else { return }
        finishSlideNow()
        let workspace = runtime.state.currentWorkspace
        let original = workspace.effectiveTheme
        requestNativeFocus?()
        let popover = SpaceThemePopover(theme: original, onChange: { [weak self] in self?.previewTheme($0) }, onClose: { [weak self] edited in
            guard let self else { return }
            self.themePopover = nil
            self.themePreview = nil
            if edited != original { _ = self.runtime.updateWorkspaceTheme(workspace.id, theme: edited) }
            self.render()
        })
        themePopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
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

    private func swipeWorkspace(_ direction: WorkspaceSwipe.Direction) {
        guard let id = neighbour(direction) else { return }
        switchWorkspace(id)
    }

    private func neighbour(_ direction: WorkspaceSwipe.Direction) -> UUID? {
        let state = runtime.state
        guard let index = state.workspaces.firstIndex(where: { $0.id == state.activeWorkspaceID }),
              let target = WorkspaceSwipe.target(from: index, direction: direction, count: state.workspaces.count) else { return nil }
        return state.workspaces[target].id
    }

    private func switchWorkspace(_ id: UUID) {
        if createSpacePage != nil { dismissCreateSpacePage() }
        guard hasStarted, root.window?.attachedSheet == nil, NSApp.modalWindow == nil,
              id != runtime.state.activeWorkspaceID else { return }
        finishSlideNow()
        let state = runtime.state
        guard let from = state.workspaces.firstIndex(where: { $0.id == state.activeWorkspaceID }),
              let to = state.workspaces.firstIndex(where: { $0.id == id }),
              beginSlide(toward: to > from ? .next : .previous, target: id) else {
            perform { runtime.activateWorkspace(id) }
            return
        }
        commitSlide(to: id)
    }

    // MARK: Workspace slide

    private func configureSwipe(_ recognizer: WorkspaceSwipeRecognizer) {
        recognizer.layout = { [weak self] in
            guard let self else { return WorkspaceSwipe.Layout(width: 268, hasPrevious: false, hasNext: false) }
            return WorkspaceSwipe.Layout(width: self.sidebarScroll.bounds.width,
                                         hasPrevious: self.neighbour(.previous) != nil, hasNext: self.neighbour(.next) != nil)
        }
        recognizer.onTrack = { [weak self] in self?.trackSlide(offset: $0) }
        recognizer.onFinish = { [weak self] direction, _ in self?.releaseSlide(direction) }
        recognizer.onPastEnd = { [weak self] in self?.createSpace() }
    }

    private var canSlide: Bool {
        hasStarted && root.window?.attachedSheet == nil && NSApp.modalWindow == nil && !pinsAnimating && createSpacePage == nil
    }

    private func trackSlide(offset: CGFloat) {
        guard !Self.reducesMotion, canSlide else { return }
        if slideReleasing { finishSlideNow() }
        if slide == nil {
            guard beginSlide(toward: nil, target: nil) else { return }
        }
        guard let slide, !slideReleasing else { return }
        let direction: WorkspaceSwipe.Direction = offset > 0 ? .previous : .next
        if !slide.hasNeighbour(direction), let id = neighbour(direction) { addSlideNeighbour(direction, id: id) }
        slide.setOffset(offset)
        let state = runtime.state
        if let index = state.workspaces.firstIndex(where: { $0.id == state.activeWorkspaceID }), slide.hasNeighbour(direction) {
            highlightPagerDot(at: abs(offset) >= slide.width / 2 ? index + (direction == .next ? 1 : -1) : index)
        }
    }

    private func highlightPagerDot(at index: Int) {
        for (position, dot) in workspacePager.arrangedSubviews.enumerated() {
            (dot as? ActionButton)?.image = pagerDot(isActive: position == index)
        }
    }

    private func releaseSlide(_ direction: WorkspaceSwipe.Direction?) {
        if Self.reducesMotion {
            if let direction, let id = neighbour(direction) { switchWorkspace(id) }
            return
        }
        guard let slide, !slideReleasing else { return }
        if let direction, let id = neighbour(direction) {
            commitSlide(to: id, direction: direction)
        } else {
            slideReleasing = true
            let state = runtime.state
            highlightPagerDot(at: state.workspaces.firstIndex { $0.id == state.activeWorkspaceID } ?? 0)
            let fraction = abs(slide.offset) / slide.width
            slide.animate(to: 0, duration: 0.2 + 0.06 * fraction) { [weak self, weak slide] in self?.endSlide(slide) }
        }
    }

    /// Pictures the list as it stands and hides the live one. `direction`/`target` prepare a keyboard-style slide whose
    /// neighbour is known up front; a gesture adds its neighbours as the fingers choose a side.
    private func beginSlide(toward direction: WorkspaceSwipe.Direction?, target: UUID?) -> Bool {
        guard canSlide, slide == nil, let stack = sidebarScroll.superview else { return false }
        entries.layoutSubtreeIfNeeded()
        let visible = entries.visibleRect
        let headerTop = spaceHeaderRow.map { entries.convert($0.bounds, from: $0).minY } ?? visible.minY
        let slideTop = min(max(headerTop, visible.minY), visible.maxY)
        let area = root.convert(sidebarScroll.frame, from: stack)
        let slide = SpaceSlide(root: root, stack: stack, listFrame: area)
        let current = capture(NSRect(x: 0, y: slideTop, width: entries.bounds.width, height: visible.maxY - slideTop),
                              top: slideTop - visible.minY)
        let fixed = slideTop > visible.minY
            ? capture(NSRect(x: 0, y: visible.minY, width: entries.bounds.width, height: slideTop - visible.minY), top: 0) : nil
        guard let current else { slide.remove(); return false }
        slide.setCurrent(current, fixedTop: fixed)
        self.slide = slide
        slideReleasing = false
        slideListTop = slideTop - visible.minY
        slideHeight = visible.maxY - slideTop
        sidebarScroll.alphaValue = 0
        if let direction, let target { addSlideNeighbour(direction, id: target) }
        return true
    }

    private func addSlideNeighbour(_ direction: WorkspaceSwipe.Direction, id: UUID) {
        guard let slide else { return }
        var state = runtime.state
        state.activeWorkspaceID = id
        previewState = state
        (root as? WorkspaceRoot)?.appearance = state.currentWorkspace.effectiveTheme.appearance
        rebuildEntries(state, pinsAnimation: nil)
        entries.layoutSubtreeIfNeeded()
        let top = spaceHeaderRow.map { entries.convert($0.bounds, from: $0).minY } ?? 0
        let height = min(slideHeight, max(entries.bounds.height - top, 0))
        let page = capture(NSRect(x: 0, y: top, width: entries.bounds.width, height: height), top: slideListTop)
        let tint = theme
        previewState = nil
        (root as? WorkspaceRoot)?.appearance = runtime.state.currentWorkspace.effectiveTheme.appearance
        rebuildEntries(runtime.state, pinsAnimation: nil)
        if let page { slide.addNeighbour(direction, page: page, theme: tint) }
    }

    private func capture(_ rect: NSRect, top: CGFloat) -> SpaceSlide.Page? {
        guard rect.width > 0, rect.height > 0, let rep = entries.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        entries.cacheDisplay(in: rect, to: rep)
        return rep.cgImage.map { SpaceSlide.Page(image: $0, size: rect.size, top: top) }
    }

    /// The model switches as the fingers lift, so the page follows at once; only the sidebar settles. The slide is
    /// handed to Core Animation before the switch, whose page work would otherwise hold the first frame back.
    private func commitSlide(to id: UUID, direction: WorkspaceSwipe.Direction? = nil) {
        guard let slide else { return }
        let side: WorkspaceSwipe.Direction = direction ?? (slide.hasNeighbour(.next) ? .next : .previous)
        slideReleasing = true
        guard slide.hasNeighbour(side) else {
            perform { runtime.activateWorkspace(id) }
            return endSlide(slide)
        }
        if Self.reducesMotion {
            slide.crossfade(to: side, duration: 0.18) { [weak self, weak slide] in self?.endSlide(slide) }
        } else {
            let target = side == .previous ? slide.width : -slide.width
            let remaining = abs(target - slide.offset) / slide.width
            slide.animate(to: target, duration: 0.12 + 0.1 * remaining) { [weak self, weak slide] in self?.endSlide(slide) }
        }
        perform { runtime.activateWorkspace(id) }
        if runtime.state.activeWorkspaceID != id { endSlide(slide) }
    }

    private func finishSlideNow() {
        guard slide != nil else { return }
        endSlide()
    }

    private func endSlide(_ finished: SpaceSlide? = nil) {
        guard let slide, finished == nil || finished === slide else { return }
        self.slide = nil
        slideReleasing = false
        slide.remove()
        sidebarScroll.alphaValue = 1
        sidebarScroll.contentView.scroll(to: .zero)
        (root as? WorkspaceRoot)?.theme = theme
    }

    /// Another Profile's workspace is shown in that Profile's own window, so its section says so.
    @objc private func showWorkspaceSwitcher() {
        guard hasStarted, let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        requestNativeFocus?()
        let state = runtime.state
        let currentProfileID = state.currentWorkspace.profileID
        var entries: [SwitcherEntry] = []
        var number = 1
        for group in state.profileGroups {
            if state.hasMultipleProfiles {
                let own = group.profile.id == currentProfileID
                entries.append(.header(title: own ? group.profile.name : "\(group.profile.name) · opens in its own window",
                                       dot: workspaceColor(state.displayColor(of: group.profile))))
            }
            for workspace in group.workspaces {
                entries.append(.item(title: workspace.name, dot: workspaceColor(workspace.color), symbol: nil,
                                     checked: workspace.id == state.activeWorkspaceID,
                                     shortcut: number <= 9 ? "⌃\(number)" : nil, enabled: true,
                                     identifier: "bato-switcher-workspace-\(number)") { [weak self] in self?.switchWorkspace(workspace.id) })
                number += 1
            }
        }
        entries.append(.separator)
        entries.append(switcherAction("New Workspace", symbol: "plus", id: "new-workspace") { [weak self] in
            self?.createSpace()
        })
        entries.append(switcherAction("New Profile…", symbol: "person.crop.circle.badge.plus", id: "new-profile") { [weak self] in
            self?.editProfile(creating: true)
        })
        entries.append(switcherAction("Rename Profile…", symbol: "pencil", id: "rename-profile") { [weak self] in
            self?.editProfile(creating: false)
        })
        entries.append(.separator)
        entries.append(switcherAction("Profile Settings", symbol: "gearshape", id: "settings") { [weak self] in
            self?.showSettings(.profiles)
        })
        switcherPopover.show(entries, relativeTo: switcherButton)
    }

    @objc private func showProfileMenu() {
        guard hasStarted, let window = root.window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        requestNativeFocus?()
        let state = runtime.state
        var entries: [SwitcherEntry] = state.profileGroups.enumerated().map { index, group in
            .item(title: group.profile.name, dot: workspaceColor(state.displayColor(of: group.profile)), symbol: nil,
                  checked: group.profile.id == state.currentWorkspace.profileID, shortcut: nil,
                  enabled: !group.workspaces.isEmpty, identifier: "bato-profile-item-\(index)") { [weak self] in
                // A Profile opens on its first workspace; other workspaces are in the switcher.
                if let first = group.workspaces.first { self?.switchWorkspace(first.id) }
            }
        }
        entries.append(.separator)
        entries.append(switcherAction("New Profile…", symbol: "person.crop.circle.badge.plus", id: "new-profile") { [weak self] in
            self?.editProfile(creating: true)
        })
        entries.append(switcherAction("Rename Profile…", symbol: "pencil", id: "rename-profile") { [weak self] in
            self?.editProfile(creating: false)
        })
        entries.append(.separator)
        entries.append(switcherAction("Profile Settings", symbol: "gearshape", id: "settings") { [weak self] in
            self?.showSettings(.profiles)
        })
        switcherPopover.show(entries, relativeTo: profileButton, edge: .minY)
    }

    private func switcherAction(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> SwitcherEntry {
        .item(title: title, dot: nil, symbol: symbol, checked: false, shortcut: nil, enabled: true,
              identifier: "bato-switcher-\(id)", action: action)
    }

    /// Asks before deleting a Profile, saying what goes with it. The launch Profile is never offered.
    private func confirmDeleteProfile(_ id: UUID) {
        guard hasStarted, id != runtime.state.launchProfileID, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil,
              let profile = runtime.state.profiles.first(where: { $0.id == id }),
              let loss = runtime.state.lossOfDeleting(profile: id) else { return }
        requestNativeFocus?()
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        let body = "This permanently deletes the Profile’s history, downloads list, logins, cookies and site data, "
            + "and removes its \(count(loss.workspaces, "workspace")), \(count(loss.pages, "page")), "
            + "\(count(loss.favorites, "favorite")) and \(count(loss.archived, "archived tab")). Its open windows close without asking. "
            + "The sidebar organization is backed up first; browsing data cannot be recovered."
        RecoverySheet.present(on: window, symbol: "trash", title: "Delete the Profile “\(profile.name)”?", body: body,
                              buttons: [.init(title: "Cancel", isDefault: true), .init(title: "Delete Profile", isDefault: false)],
                              cancelIndex: 0) { [weak self] index in
            guard index == 1 else { return }
            DispatchQueue.main.async { [weak self] in self?.deleteProfile(id) }
        }
    }

    private func deleteProfile(_ id: UUID) {
        guard runtime.deleteProfile(id) else {
            guard let window = root.window, window.attachedSheet == nil else { return }
            RecoverySheet.present(on: window, symbol: "exclamationmark.triangle", title: "The Profile couldn’t be deleted",
                                  body: "Nothing was removed. Close any dialog in that Profile’s window and try again.",
                                  buttons: [.init(title: "OK", isDefault: true)], cancelIndex: 0) { _ in }
            return
        }
        BlockingHost.shared.profiles?.removeProfile(id.uuidString)
        render()
    }

    /// Asks before deleting a workspace, saying what goes with it. A Profile's last workspace is never offered.
    private func confirmDeleteWorkspace(_ id: UUID) {
        guard hasStarted, runtime.state.canDeleteWorkspace(id), let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil,
              let workspace = runtime.state.workspaces.first(where: { $0.id == id }),
              let loss = runtime.state.lossOfDeleting(workspace: id) else { return }
        requestNativeFocus?()
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        let body = "This removes the workspace’s \(count(loss.pages, "pin and tab")) and \(count(loss.archived, "archived tab")) "
            + "and closes its open pages without asking. Browsing history and logins stay with the Profile. "
            + "The sidebar organization is backed up first."
        RecoverySheet.present(on: window, symbol: "trash", title: "Delete the workspace “\(workspace.name)”?", body: body,
                              buttons: [.init(title: "Cancel", isDefault: true), .init(title: "Delete Workspace", isDefault: false)],
                              cancelIndex: 0) { [weak self] index in
            guard index == 1 else { return }
            DispatchQueue.main.async { [weak self] in self?.deleteWorkspace(id) }
        }
    }

    private func deleteWorkspace(_ id: UUID) {
        guard runtime.deleteWorkspace(id) else {
            render()
            guard let window = root.window, window.attachedSheet == nil else { return }
            RecoverySheet.present(on: window, symbol: "exclamationmark.triangle", title: "The workspace couldn’t be deleted",
                                  body: "Nothing was removed. Try again.",
                                  buttons: [.init(title: "OK", isDefault: true)], cancelIndex: 0) { _ in }
            return
        }
        render()
    }

    private func editProfile(creating: Bool) {
        guard hasStarted, profileEditor == nil, let window = root.window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let state = runtime.state
        guard let profile = state.profiles.first(where: { $0.id == state.currentWorkspace.profileID }) else { return }
        requestNativeFocus?()
        func failure() -> String {
            runtime.lastError == .saveFailed ? "Changes couldn’t be saved. Reopen Bato to reload organization."
                : "The Profile couldn’t be saved. Check its name and try again."
        }
        let duplicate = "Another Profile already has that name."
        let editor: ProfileEditor
        if creating {
            let used = Set(state.profiles.map { state.displayColor(of: $0).uppercased() })
            let color = sidebarColorPalette.map(\.hex).first { !used.contains($0) } ?? sidebarColorPalette[0].hex
            editor = ProfileEditor(creating: true, name: "", color: color) { [weak self] name, color, workspaceName in
                guard let self else { return "Bato is no longer available." }
                guard self.runtime.state.isProfileNameAvailable(name) else { return duplicate }
                guard self.runtime.createProfile(name: name, color: color, workspaceName: workspaceName.isEmpty ? name : workspaceName,
                                                 deferPageSelection: true) else { return failure() }
                self.render()
                return nil
            }
        } else {
            let profileID = profile.id
            editor = ProfileEditor(creating: false, name: profile.name, color: state.displayColor(of: profile)) { [weak self] name, color, _ in
                guard let self else { return "Bato is no longer available." }
                guard self.runtime.state.isProfileNameAvailable(name, excluding: profileID) else { return duplicate }
                guard self.runtime.updateProfile(profileID, name: name, color: color) else { return failure() }
                self.render()
                return nil
            }
        }
        profileEditor = editor
        guard let sheet = editor.window else { profileEditor = nil; return }
        window.beginSheet(sheet) { [weak self] response in
            guard let self else { return }
            self.profileEditor = nil
            guard creating, response == .OK else { return }
            // The new Profile's workspace was selected with its page work deferred; finish it after the sheet.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.root.window === window else { return }
                if let request = self.requestPagePresentation { request() } else { self.resumeCommittedSelection() }
            }
        }
        editor.focusName()
    }

    /// Control-1…9 follow the switcher's order, which groups workspaces by Profile.
    private func switchToShortcut(_ number: Int) -> Bool {
        guard hasStarted, let id = runtime.state.switcherWorkspaceID(forShortcut: number) else { return false }
        switchWorkspace(id)
        return true
    }

}

/// Resolve semantic colors while drawing, rather than caching appearance-bound
/// CGColors. Display-option changes redraw the same opaque native surfaces.
@MainActor
class AdaptiveSidebarView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        AppearanceWatcher.start()
        NotificationCenter.default.addObserver(self, selector: #selector(displayOptionsChanged),
                                               name: AppearanceWatcher.didChange, object: nil)
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
    private var hovered = false { didSet { close.alphaValue = hovered ? 1 : 0 } }
    var hoverChanged: ((Bool) -> Void)?
    private let close: NSButton
    private var tracking: NSTrackingArea?
    init(select: NSButton, close: NSButton, tile: Bool, selected: Bool, accent: NSColor) {
        self.selected = selected
        self.accent = accent
        self.tile = tile
        self.close = close
        super.init(frame: .zero)
        // The hidden close stays in the accessibility tree and still takes clicks; hover only reveals it.
        close.alphaValue = 0
        select.translatesAutoresizingMaskIntoConstraints = false
        close.translatesAutoresizingMaskIntoConstraints = false
        addSubview(select)
        addSubview(close)
        heightAnchor.constraint(equalToConstant: tile ? SidebarStyle.tileHeight : SidebarStyle.rowHeight).isActive = true
        close.widthAnchor.constraint(equalToConstant: 20).isActive = true
        close.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if tile {
            NSLayoutConstraint.activate([
                select.leadingAnchor.constraint(equalTo: leadingAnchor),
                select.trailingAnchor.constraint(equalTo: trailingAnchor),
                select.topAnchor.constraint(equalTo: topAnchor),
                select.bottomAnchor.constraint(equalTo: bottomAnchor),
                close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                close.topAnchor.constraint(equalTo: topAnchor, constant: 1)
            ])
        } else {
            NSLayoutConstraint.activate([
                select.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
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
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true; hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true; hoverChanged?(false) }
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return super.otherMouseUp(with: event)
        }
        close.performClick(nil)
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: SidebarMetrics.cornerRadius, yRadius: SidebarMetrics.cornerRadius)
        if let fill = SidebarStyle.rowFill(selected: selected, hovered: hovered, tile: tile) {
            fill.setFill()
        } else {
            NSColor.clear.setFill()
        }
        path.fill()
    }
}

private struct SidebarPairHalf {
    let select: ActionButton
    let close: ActionButton
    let card: SidebarHoverCardContent
    /// The pane's page is the selected one while the pair is not displayed (a saved pair shown as a single page).
    let isFocused: Bool
}

/// Arc's split row: one rounded pill, two equal halves side by side. The whole pill takes the selected fill
/// while the pair is shown; each half shows its own close on hover (or on both while selected).
@MainActor
private final class SidebarPairView: AdaptiveSidebarView {
    private let halves: [SidebarPairHalf]
    private let containers: [NSView]
    private let selected: Bool
    private var hoveredHalf: Int? {
        didSet {
            guard hoveredHalf != oldValue else { return }
            needsDisplay = true
            updateCloseVisibility()
            hoverChanged?(hoveredHalf)
        }
    }
    var hoverChanged: ((Int?) -> Void)?
    private var tracking: NSTrackingArea?
    let pairClose: ActionButton

    init(halves: [SidebarPairHalf], pairClose: ActionButton, selected: Bool, accent: NSColor) {
        self.halves = halves
        self.pairClose = pairClose
        self.selected = selected
        containers = halves.map { _ in NSView() }
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: SidebarStyle.rowHeight).isActive = true
        for (index, half) in halves.enumerated() {
            let container = containers[index]
            container.translatesAutoresizingMaskIntoConstraints = false
            addSubview(container)
            half.select.translatesAutoresizingMaskIntoConstraints = false
            half.close.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(half.select)
            container.addSubview(half.close)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: topAnchor),
                container.bottomAnchor.constraint(equalTo: bottomAnchor),
                half.select.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                half.select.trailingAnchor.constraint(equalTo: half.close.leadingAnchor, constant: -1),
                half.select.topAnchor.constraint(equalTo: container.topAnchor),
                half.select.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                half.close.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -3),
                half.close.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                half.close.widthAnchor.constraint(equalToConstant: 20),
                half.close.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        pairClose.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pairClose)
        NSLayoutConstraint.activate([
            pairClose.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            pairClose.centerYAnchor.constraint(equalTo: centerYAnchor),
            pairClose.widthAnchor.constraint(equalToConstant: 20),
            pairClose.heightAnchor.constraint(equalToConstant: 24),
            containers[0].leadingAnchor.constraint(equalTo: leadingAnchor),
            containers[1].trailingAnchor.constraint(equalTo: trailingAnchor),
            containers[0].trailingAnchor.constraint(equalTo: containers[1].leadingAnchor),
            containers[0].widthAnchor.constraint(equalTo: containers[1].widthAnchor)
        ])
        updateCloseVisibility()
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func halfView(_ index: Int) -> NSView { containers[index] }

    /// A displayed pair shows a close on each half while hovered; a hidden one shows a single close, at the far
    /// right, for the whole pair.
    private func updateCloseVisibility() {
        for half in halves {
            half.close.isHidden = !selected
            half.close.alphaValue = hoveredHalf != nil ? 1 : 0
        }
        pairClose.isHidden = selected
        pairClose.alphaValue = hoveredHalf != nil ? 1 : 0
    }

    private func half(at event: NSEvent) -> Int {
        convert(event.locationInWindow, from: nil).x < bounds.midX ? 0 : 1
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hoveredHalf = half(at: event) }
    override func mouseMoved(with event: NSEvent) { hoveredHalf = half(at: event) }
    override func mouseExited(with event: NSEvent) { hoveredHalf = nil }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return super.otherMouseUp(with: event)
        }
        (selected ? halves[half(at: event)].close : pairClose).performClick(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = SidebarMetrics.cornerRadius
        let pill = bounds.insetBy(dx: 0.5, dy: 1)
        if selected {
            SidebarStyle.rowFill(selected: true, hovered: false, tile: false)?.setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            // Each half sits in the container as a lighter rounded rect, with a gap between them.
            let inner = pill.insetBy(dx: 3.5, dy: 3.5)
            let width = (inner.width - 4) / 2
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            for index in 0..<2 {
                let rect = NSRect(x: inner.minX + CGFloat(index) * (width + 4), y: inner.minY, width: width, height: inner.height)
                NSBezierPath(roundedRect: rect, xRadius: radius - 2, yRadius: radius - 2).fill()
            }
        } else if hoveredHalf != nil {
            SidebarStyle.rowFill(selected: false, hovered: true, tile: false)?.setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
        }
        if !selected {
            NSColor.labelColor.withAlphaComponent(0.30).setFill()
            NSBezierPath(rect: NSRect(x: bounds.midX - 0.5, y: bounds.midY - 8, width: 1, height: 16)).fill()
        }
    }
}

/// A non-page sidebar row (New Tab) with the same metrics and hover wash as a page row.
@MainActor
private final class SidebarActionRow: AdaptiveSidebarView {
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(button: NSButton) {
        super.init(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SidebarStyle.rowHeight),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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
    /// A slide moves the row without telling its tracking area, so hover is re-read from the pointer.
    func refreshHover() {
        guard let window else { return }
        hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        needsDisplay = true
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshHover() }
    override func draw(_ dirtyRect: NSRect) {
        guard let fill = SidebarStyle.rowFill(selected: false, hovered: hovered, tile: false) else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: SidebarMetrics.cornerRadius,
                     yRadius: SidebarMetrics.cornerRadius).fill()
    }
}

/// One radius and one side inset for every sidebar surface, so rows and the pill read as a set.
enum SidebarMetrics {
    static let cornerRadius: CGFloat = 10
    static let sideInset: CGFloat = 10
    /// Must equal kNativeSidebarTopRowHeight in the engine overlay: the sidebar spans the window top and its first row shares the traffic lights' row.
    static let topRowHeight: CGFloat = 46
    /// How far the heading row sits below the window top: the 8pt card margin (ContentCardFrameView.margin) plus 3pt,
    /// so it shares the toolbar and traffic lights centre line.
    static let headingDrop: CGFloat = 11
    /// Space the three traffic lights occupy at the row's leading edge, net of the side inset.
    static let trafficLightClearance: CGFloat = 62
    /// Gap between the green light and the workspace label, net of the row's own 2pt item spacing.
    static let trafficLightGap: CGFloat = 6
    /// The show-sidebar button's side. With the traffic light gap and 4pt of trailing air it must equal
    /// kNativeSidebarToggleSlot (38) in the engine overlay, which is where Chromium's toolbar starts after the lights.
    static let revealButtonSide: CGFloat = 28
    /// Arc fades the pinned rows in over roughly this long while the content below slides.
    static let pinsAnimationDuration: TimeInterval = 0.22
    /// Space under a collapsed Space header, before the divider.
    static let collapsedPinsGap: CGFloat = 18
}

@MainActor
public func sidebarSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: size, height: size))
    return image.withSymbolConfiguration(.init(pointSize: size, weight: weight)) ?? image
}

/// Empty space in the top row; the sidebar covers the window's own drag area.
@MainActor
private final class WindowDragView: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

@MainActor
private final class SidebarScrollView: NSScrollView {
    let swipe = WorkspaceSwipeRecognizer()
    override func scrollWheel(with event: NSEvent) {
        if !swipe.handle(event) { super.scrollWheel(with: event) }
    }
}

@MainActor
private final class WorkspaceRoot: AdaptiveSidebarView {
    let swipe = WorkspaceSwipeRecognizer()
    override func scrollWheel(with event: NSEvent) {
        if !swipe.handle(event) { super.scrollWheel(with: event) }
    }
    var theme = SpaceTheme(color: "#B47879") {
        didSet {
            appearance = theme.appearance
            needsDisplay = true
        }
    }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        ThemeFill.draw(theme, in: bounds, appearance: effectiveAppearance)
    }
    var keyEquivalentsEnabled = true
    var pointerChanged: ((Bool) -> Void)?
    private var pointerTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTracking = area
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?(true) }
    override func mouseExited(with event: NSEvent) { pointerChanged?(false) }
    var windowChanged: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowChanged?()
    }
    var newTab: (() -> Void)?
    var closeSelection: (() -> Void)?
    var editAddress: (() -> Bool)?
    var copyLink: (() -> Bool)?
    var switchToWorkspace: ((Int) -> Bool)?
    override var isFlipped: Bool { true }
    // Clicks on empty sidebar space reach this view, and the sidebar covers the window's own drag area.
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
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
        case (.control, let digit?) where digit.count == 1 && "123456789".contains(digit):
            if switchToWorkspace?(Int(digit)!) == true { return true }
        default: break
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A tab menu whose Mute item follows the page's audio as the menu opens.
@MainActor
private final class PageMenu: NSMenu {
    private var refreshMute: (() -> Void)?

    func add(muteItemFor entryID: UUID) {
        let item = ActionMenuItem(title: "Mute Tab") { TabAudioCenter.shared.toggleMute(entryID: entryID) }
        addItem(item)
        refreshMute = { [weak item] in
            let state = TabAudioCenter.shared.states[entryID]
            item?.title = state?.muted == true ? "Unmute Tab" : "Mute Tab"
            item?.isEnabled = state != nil
        }
        refreshMute?()
    }

    override func update() {
        refreshMute?()
        super.update()
    }
}

/// A brief "Copied" pill at the top of the window, like Arc's.
@MainActor
private enum CopiedToast {
    private static weak var current: NSView?

    static func show(in window: NSWindow) {
        guard let content = window.contentView else { return }
        current?.removeFromSuperview()
        let label = NSTextField(labelWithString: "Copied")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let pill = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 28, height: 28))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        pill.layer?.cornerRadius = 14
        label.frame.origin = NSPoint(x: 14, y: (pill.frame.height - label.frame.height) / 2)
        pill.addSubview(label)
        pill.frame.origin = NSPoint(x: (content.bounds.width - pill.frame.width) / 2,
                                    y: content.bounds.height - pill.frame.height - 66)
        pill.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        pill.setAccessibilityLabel("Copied")
        content.addSubview(pill, positioned: .above, relativeTo: nil)
        current = pill
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak pill] in
            guard let pill, pill === current else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                pill.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { pill.removeFromSuperview() } })
        }
    }
}

@MainActor
private final class ActionButton: NSButton {
    private let invoke: () -> Void
    /// Set only on page rows: a press that moves past the drag threshold starts a drag instead of a click.
    var beginDrag: ((NSEvent) -> Void)?
    private var dropHandler: ((UUID) -> Bool)?
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

    override func mouseDown(with event: NSEvent) {
        guard let beginDrag, isEnabled, !event.modifierFlags.contains(.control) else { return super.mouseDown(with: event) }
        let origin = event.locationInWindow
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { performClick(nil) }
                return
            }
            if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) > 4 {
                beginDrag(next)
                return
            }
        }
    }

    func acceptsEntryDrops(_ handler: @escaping (UUID) -> Bool) {
        dropHandler = handler
        registerForDraggedTypes([.batoEntry])
        wantsLayer = true
        layer?.cornerRadius = 7
    }

    private func droppedEntry(_ sender: any NSDraggingInfo) -> UUID? {
        sender.draggingPasteboard.string(forType: .batoEntry).flatMap(UUID.init(uuidString:))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard dropHandler != nil, droppedEntry(sender) != nil else { return [] }
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor
        return .move
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { layer?.backgroundColor = nil }
    override func draggingEnded(_ sender: any NSDraggingInfo) { layer?.backgroundColor = nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        layer?.backgroundColor = nil
        guard let id = droppedEntry(sender) else { return false }
        return dropHandler?(id) ?? false
    }
}

@MainActor
final class ActionMenuItem: NSMenuItem {
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

private let sidebarColorPalette: [(name: String, hex: String)] = [
    ("Rose", "#B47879"), ("Ocean", "#527FAD"), ("Sage", "#6D8B70"),
    ("Lavender", "#8975A8"), ("Amber", "#B38847"), ("Slate", "#76818F")]

@MainActor
private func pagerDot(isActive: Bool) -> NSImage {
    let size: CGFloat = isActive ? 7 : 5
    return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
        NSColor.labelColor.withAlphaComponent(isActive ? 0.95 : 0.4).setFill()
        NSBezierPath(ovalIn: NSRect(x: (rect.width - size) / 2, y: (rect.height - size) / 2, width: size, height: size)).fill()
        return true
    }
}

@MainActor
private func colorDot(_ color: NSColor, size: CGFloat = 9) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        return true
    }
}

/// Uses a sheet-local draft: Cancel never publishes organization changes.
@MainActor
private final class WorkspaceEditor: NSWindowController {
    private let nameField = NSTextField(string: "")
    private let colorPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let save: (String, String) -> String?
    private var colors: [String] = []

    init(creating: Bool = false, name: String, color: String, save: @escaping (String, String) -> String?) {
        self.save = save
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = creating ? "New Space" : "Edit workspace"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        nameField.stringValue = name
        nameField.setAccessibilityLabel("Workspace name")
        nameField.setAccessibilityIdentifier("bato-workspace-name")
        nameField.cell?.sendsActionOnEndEditing = false
        colorPicker.setAccessibilityLabel("Workspace color")
        colorPicker.setAccessibilityIdentifier("bato-workspace-color")
        for (title, value) in sidebarColorPalette {
            colorPicker.addItem(withTitle: title)
            colorPicker.lastItem?.image = colorDot(workspaceColor(value))
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
        let apply = ActionButton(title: creating ? "Create" : "Save") { [weak self] in self?.saveDraft() }
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
            SidebarStyle.fitSheet(window, to: stack)
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

/// Sheet-local draft for a new or renamed Profile; Cancel publishes nothing.
@MainActor
private final class ProfileEditor: NSWindowController {
    private let nameField = NSTextField(string: "")
    private let workspaceField = NSTextField(string: "")
    private let colorPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let save: (String, String, String) -> String?
    private var colors: [String] = []

    init(creating: Bool, name: String, color: String, save: @escaping (String, String, String) -> String?) {
        self.save = save
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = creating ? "New Profile" : "Rename Profile"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        nameField.stringValue = name
        nameField.setAccessibilityLabel("Profile name")
        nameField.setAccessibilityIdentifier("bato-profile-name")
        nameField.cell?.sendsActionOnEndEditing = false
        workspaceField.placeholderString = "Same as Profile name"
        workspaceField.setAccessibilityLabel("First workspace name")
        workspaceField.setAccessibilityIdentifier("bato-profile-first-workspace")
        colorPicker.setAccessibilityLabel("Profile color")
        colorPicker.setAccessibilityIdentifier("bato-profile-color")
        for (title, value) in sidebarColorPalette {
            colorPicker.addItem(withTitle: title)
            colorPicker.lastItem?.image = colorDot(workspaceColor(value))
            colors.append(value)
        }
        if let index = colors.firstIndex(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) {
            colorPicker.selectItem(at: index)
        } else {
            colorPicker.addItem(withTitle: "Current color (\(color))")
            colorPicker.lastItem?.image = colorDot(workspaceColor(color))
            colors.append(color)
            colorPicker.selectItem(at: colors.count - 1)
        }
        let note = NSTextField(wrappingLabelWithString: creating
            ? "A Profile keeps its own logins, cookies and site data, and opens in its own window."
            : "Renaming keeps this Profile’s logins and site data.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityIdentifier("bato-profile-error")
        let cancel = ActionButton(title: "Cancel") { [weak self] in self?.dismiss(.cancel) }
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier("bato-profile-cancel")
        let apply = ActionButton(title: creating ? "Create" : "Save") { [weak self] in self?.saveDraft() }
        apply.keyEquivalent = "\r"
        apply.setAccessibilityIdentifier("bato-profile-save")
        window.defaultButtonCell = apply.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, apply])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        var rows: [NSView] = [NSTextField(labelWithString: "Name"), nameField,
                              NSTextField(labelWithString: "Color"), colorPicker]
        if creating { rows += [NSTextField(labelWithString: "First workspace"), workspaceField] }
        rows += [note, errorLabel, buttons]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            var constraints = [
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
                nameField.widthAnchor.constraint(equalTo: stack.widthAnchor),
                colorPicker.widthAnchor.constraint(equalTo: stack.widthAnchor),
                note.widthAnchor.constraint(equalTo: stack.widthAnchor),
                errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ]
            if creating { constraints.append(workspaceField.widthAnchor.constraint(equalTo: stack.widthAnchor)) }
            NSLayoutConstraint.activate(constraints)
            SidebarStyle.fitSheet(window, to: stack)
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
            errorLabel.stringValue = "Enter a Profile name."
            focusName()
            return
        }
        let index = colorPicker.indexOfSelectedItem
        guard colors.indices.contains(index) else { return }
        let workspaceName = workspaceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = save(name, colors[index], workspaceName) {
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

/// Paints the sidebar's tint in the gutter around the page card, with a rounded cut-out where the
/// content shows through. The engine reserves the same gutter in Chrome's layout; it is purely
/// visual and never takes input, so pointer events reach the page and toolbar underneath.
@MainActor
public final class ContentCardFrameView: NSView {
    public static let margin: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    var theme: SpaceTheme {
        didSet {
            appearance = theme.appearance
            needsDisplay = true
        }
    }
    /// Width the docked sidebar reserves, 0 when it is hidden or floating; the card starts one margin after it.
    public var sidebarWidth: CGFloat = 0 { didSet { needsDisplay = true } }
    /// Width of the sidebar itself, docked or floating; it is drawn by the sidebar, not by this view.
    public var sidebarCoverWidth: CGFloat = 0 { didSet { needsDisplay = true; updateShowSidebarButton() } }
    public var isCardShown = true { didSet { isHidden = !isCardShown; updateShowSidebarButton() } }
    /// Displayed split panes in this view's flipped coordinates; each is its own rounded card with the tint between.
    public var paneCards: [NSRect] = [] {
        didSet {
            guard paneCards != oldValue else { return }
            needsDisplay = true
            updateSplitButton()
            updateGrabber()
        }
    }
    /// Pane that holds focus, outlined in the workspace accent.
    public var focusedPane: Int? { didSet { needsDisplay = true } }
    /// Called with the first pane's share of the space while the grabber between two panes is dragged.
    var onSplitRatio: ((Double) -> Void)?
    private var grabberHovered = false { didSet { if grabberHovered != oldValue { needsDisplay = true } } }
    private var grabberDragging = false { didSet { if grabberDragging != oldValue { needsDisplay = true } } }
    private var grabberTracking: NSTrackingArea?
    private var grabberMonitor: Any?
    /// The toolbar's split button, shown only while no pair is displayed.
    var onAddSplit: ((SplitSide) -> Void)?
    var canAddSplit = false { didSet { updateSplitButton() } }
    private let splitToolbarButton = NSButton(frame: .zero)
    /// A workspace without a selected tab shows a blank card instead of the engine's placeholder page.
    public var showsEmptyState = false {
        didSet {
            guard showsEmptyState != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    public static let emptyHint = "Press ⌘T to open a tab"
    var onShowSidebar: (() -> Void)?
    private let showSidebarButton = NSButton(frame: .zero)

    /// The way back to a hidden sidebar; once the sidebar is docked or floating its own header toggle takes over.
    static func showsSidebarButton(sidebarCoverWidth: CGFloat) -> Bool { sidebarCoverWidth == 0 }

    init(theme: SpaceTheme) {
        self.theme = theme
        super.init(frame: .zero)
        appearance = theme.appearance
        autoresizingMask = [.width, .height]
        // Sibling layers composite by zPosition, not subview order, so Chromium re-adding a native
        // view (new tab, DevTools, Peek) above this one cannot cover the gutter.
        wantsLayer = true
        layer?.zPosition = 1000
        configureShowSidebarButton()
        configureSplitButton()
        AppearanceWatcher.start()
        NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                               name: AppearanceWatcher.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    @objc private func redraw() { needsDisplay = true }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override var isFlipped: Bool { true }
    /// The empty card covers Chrome's toolbar and blank page, so it must swallow their clicks too.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard showsEmptyState, !isHidden, cardRect.contains(convert(point, from: superview)) else { return nil }
        return self
    }
    public override func isAccessibilityElement() -> Bool { showsEmptyState }
    public override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    public override func accessibilityLabel() -> String? { Self.emptyHint }
    public override func accessibilityIdentifier() -> String { "bato-empty-space" }

    private func configureShowSidebarButton() {
        showSidebarButton.image = sidebarSymbol("sidebar.left", size: 13)
        showSidebarButton.imagePosition = .imageOnly
        showSidebarButton.isBordered = false
        showSidebarButton.bezelStyle = .recessed
        showSidebarButton.contentTintColor = .secondaryLabelColor
        showSidebarButton.setAccessibilityLabel("Show sidebar")
        showSidebarButton.setAccessibilityIdentifier("bato-show-sidebar")
        showSidebarButton.toolTip = "Show sidebar (⌘S)"
        showSidebarButton.target = self
        showSidebarButton.action = #selector(showSidebar)
        updateShowSidebarButton()
    }

    @objc private func showSidebar() { onShowSidebar?() }

    private func configureSplitButton() {
        splitToolbarButton.image = sidebarSymbol("rectangle.split.2x1", size: 13)
        splitToolbarButton.imagePosition = .imageOnly
        splitToolbarButton.isBordered = false
        splitToolbarButton.bezelStyle = .recessed
        splitToolbarButton.contentTintColor = .secondaryLabelColor
        splitToolbarButton.setAccessibilityLabel("Split view")
        splitToolbarButton.setAccessibilityIdentifier("bato-toolbar-split")
        splitToolbarButton.toolTip = "Split view"
        splitToolbarButton.target = self
        splitToolbarButton.action = #selector(showSplitMenu)
        updateSplitButton()
    }

    @objc private func showSplitMenu() {
        let menu = makeSplitMenu(isEnabled: canAddSplit) { [weak self] side in self?.onAddSplit?(side) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: splitToolbarButton.bounds.height + 4), in: splitToolbarButton)
    }

    private func updateSplitButton() {
        splitToolbarButton.isHidden = !isCardShown || !paneCards.isEmpty || showsEmptyState
        needsLayout = true
    }

    private func updateShowSidebarButton() {
        showSidebarButton.isHidden = !isCardShown || !Self.showsSidebarButton(sidebarCoverWidth: sidebarCoverWidth)
        needsLayout = true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { showSidebarButton.removeFromSuperview(); splitToolbarButton.removeFromSuperview() }
        needsLayout = true
    }

    /// The button lives beside the traffic lights, in their titlebar container: Chromium's content view takes every
    /// click over its own toolbar, so a button inside the window's content area would never be hit.
    public override func layout() {
        super.layout()
        let side = SidebarMetrics.revealButtonSide
        guard let window, let zoom = window.standardWindowButton(.zoomButton), let container = zoom.superview else { return }
        if showSidebarButton.superview !== container { container.addSubview(showSidebarButton) }
        showSidebarButton.frame = NSRect(x: zoom.frame.maxX + SidebarMetrics.trafficLightGap, y: zoom.frame.midY - side / 2,
                                         width: side, height: side)
        if splitToolbarButton.superview !== container { container.addSubview(splitToolbarButton) }
        // The engine keeps Chrome's toolbar clear of this slot (kNativeSplitButtonSlot).
        splitToolbarButton.frame = NSRect(x: container.bounds.width - Self.margin - 6 - side, y: zoom.frame.midY - side / 2,
                                          width: side, height: side)
    }

    // MARK: Split grabber

    /// The strip between two panes that takes the resize drag, in this view's coordinates; nil unless a pair is shown.
    var grabberHitRect: NSRect? {
        guard paneCards.count == 2 else { return nil }
        return SplitGrabber.hitRect(first: paneCards[0], second: paneCards[1])
    }

    /// The pill drawn in the middle of the gap.
    var grabberPillRect: NSRect? {
        guard paneCards.count == 2 else { return nil }
        return SplitGrabber.pillRect(first: paneCards[0], second: paneCards[1])
    }

    private func updateGrabber() {
        if let grabberTracking { removeTrackingArea(grabberTracking) }
        grabberTracking = nil
        if let hit = grabberHitRect {
            let area = NSTrackingArea(rect: hit, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
            addTrackingArea(area)
            grabberTracking = area
            if grabberMonitor == nil {
                grabberMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                    nonisolated(unsafe) let unsafeEvent = event
                    let consumed = MainActor.assumeIsolated { self?.routeGrabber(unsafeEvent) == true }
                    return consumed ? nil : event
                }
            }
        } else {
            grabberHovered = false
            grabberDragging = false
            if let grabberMonitor { NSEvent.removeMonitor(grabberMonitor) }
            grabberMonitor = nil
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === grabberTracking else { return super.mouseEntered(with: event) }
        grabberHovered = true
        resizeCursor.push()
    }

    public override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === grabberTracking else { return super.mouseExited(with: event) }
        grabberHovered = false
        if !grabberDragging { NSCursor.pop() }
    }

    private var resizeCursor: NSCursor {
        guard paneCards.count == 2 else { return .arrow }
        return SplitGrabber.isHorizontal(first: paneCards[0], second: paneCards[1]) ? .resizeLeftRight : .resizeUpDown
    }

    /// True when the event belongs to a grabber drag. Chromium's views sit above this one, so the press is taken here.
    private func routeGrabber(_ event: NSEvent) -> Bool {
        guard event.window === window, paneCards.count == 2, !isHidden else { return false }
        let point = convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            guard let hit = grabberHitRect, hit.contains(point) else { return false }
            grabberDragging = true
            return true
        case .leftMouseDragged:
            guard grabberDragging else { return false }
            let ratio = SplitGrabber.ratio(at: point, first: paneCards[0], second: paneCards[1])
            if abs(ratio - lastGrabberRatio) > 0.004 {
                lastGrabberRatio = ratio
                onSplitRatio?(ratio)
            }
            resizeCursor.set()
            return true
        case .leftMouseUp:
            guard grabberDragging else { return false }
            grabberDragging = false
            if !(grabberHitRect?.contains(point) ?? false) { NSCursor.pop() }
            return true
        default:
            return false
        }
    }
    private var lastGrabberRatio = 0.5

    /// The page card in screen coordinates (y up), for anchoring panels to it.
    var cardRectOnScreen: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(cardRect, to: nil))
    }

    private var cardRect: NSRect {
        let margin = Self.margin
        let leading = sidebarWidth + margin
        return NSRect(x: leading, y: margin, width: max(0, bounds.width - leading - margin),
                      height: max(0, bounds.height - 2 * margin))
    }

    /// One card normally; one per pane while a pair is displayed.
    private var cardPaths: [NSBezierPath] {
        let radius = paneCards.isEmpty ? Self.cornerRadius : SplitPaneChrome.paneCornerRadius
        return (paneCards.isEmpty ? [cardRect] : paneCards).map {
            NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius)
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let paths = cardPaths
        let card = NSBezierPath()
        paths.forEach { card.append($0) }
        let ring = NSBezierPath(rect: bounds)
        ring.append(card)
        ring.windingRule = .evenOdd
        NSGraphicsContext.saveGraphicsState()
        ring.addClip()
        NSBezierPath(rect: NSRect(x: sidebarCoverWidth, y: 0, width: max(0, bounds.width - sidebarCoverWidth), height: bounds.height)).addClip()
        ThemeFill.draw(theme, in: bounds, appearance: effectiveAppearance)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(effectiveAppearance.isDark ? 0.45 : 0.22)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.black.setFill()
        card.fill()
        NSShadow().set()
        NSColor.labelColor.withAlphaComponent(0.14).setStroke()
        card.lineWidth = 1
        card.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if let focusedPane, paneCards.indices.contains(focusedPane) { drawFocus(of: paneCards[focusedPane], outside: ring) }
        if let pill = grabberPillRect {
            let active = grabberHovered || grabberDragging
            let dark = effectiveAppearance.isDark
            (dark ? (active ? NSColor(srgbRed: 0.58, green: 0.57, blue: 0.60, alpha: 1) : NSColor(srgbRed: 0.34, green: 0.31, blue: 0.36, alpha: 1))
                  : NSColor.black.withAlphaComponent(active ? 0.5 : 0.25)).setFill()
            NSBezierPath(roundedRect: pill, xRadius: min(pill.width, pill.height) / 2, yRadius: min(pill.width, pill.height) / 2).fill()
        }
        if showsEmptyState { drawEmptyState(in: paths[0]) }
    }

    /// Arc's focused pane: a 2pt outline inside the pane's bounds and a soft glow that only shows between panes.
    private func drawFocus(of pane: NSRect, outside ring: NSBezierPath) {
        let radius = SplitPaneChrome.paneCornerRadius
        let width = SplitPaneChrome.focusOutlineWidth
        NSGraphicsContext.saveGraphicsState()
        ring.addClip()
        NSBezierPath(rect: NSRect(x: sidebarCoverWidth, y: 0, width: max(0, bounds.width - sidebarCoverWidth), height: bounds.height)).addClip()
        let glow = NSShadow()
        glow.shadowColor = Self.focusColor.withAlphaComponent(0.55)
        glow.shadowBlurRadius = SplitPaneChrome.focusGlowBlur
        glow.shadowOffset = .zero
        glow.set()
        Self.focusColor.setFill()
        NSBezierPath(roundedRect: pane, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
        let outline = NSBezierPath(roundedRect: pane.insetBy(dx: width / 2, dy: width / 2),
                                   xRadius: radius - width / 2, yRadius: radius - width / 2)
        outline.lineWidth = width
        Self.focusColor.setStroke()
        outline.stroke()
    }

    /// Arc's focus violet, fixed rather than following the Space colour.
    static let focusColor = NSColor(srgbRed: 0x4f / 255, green: 0x40 / 255, blue: 0xf9 / 255, alpha: 1)

    private func drawEmptyState(in card: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        ThemeFill.drawLifted(theme, in: cardRect, appearance: effectiveAppearance)
        NSGraphicsContext.restoreGraphicsState()
        let text = NSAttributedString(string: Self.emptyHint, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.55)])
        let size = text.size()
        let rect = cardRect
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}

/// Arc's Space header above the pinned section. Idle it shows the Space icon; on hover (and always while the
/// section is collapsed) the icon becomes a chevron, and a trailing ⋯ appears. Clicking toggles the section.
@MainActor
private final class SpaceHeaderRow: AdaptiveSidebarView {
    static let height: CGFloat = 36
    private static let labelX: CGFloat = 36
    private let color: NSColor
    private let icon: String?
    private let name: String
    private lazy var nameButton = ActionButton(title: name) { [weak self] in self?.toggle?() }
    private lazy var actions = ActionButton(title: "") { [weak self] in self?.showActions?() }
    private var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            actions.alphaValue = hovered ? 1 : 0
            needsDisplay = true
            hoverChanged?(hovered)
        }
    }
    private var tracking: NSTrackingArea?
    var toggle: (() -> Void)?
    var showActions: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    var actionsAnchor: NSView { actions }

    /// 0 points the chevron down (expanded), 1 points it right (collapsed). Animatable through `animator()`.
    @objc dynamic var chevronTurn: CGFloat = 0 { didSet { needsDisplay = true } }
    private var isCollapsed: Bool

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "chevronTurn" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    init(name: String, color: NSColor, icon: String?, collapsed: Bool) {
        self.name = name
        self.color = color
        self.icon = icon
        isCollapsed = collapsed
        super.init(frame: .zero)
        chevronTurn = collapsed ? 1 : 0
        nameButton.isBordered = false
        nameButton.bezelStyle = .recessed
        nameButton.focusRingType = .none
        nameButton.alignment = .left
        nameButton.font = .systemFont(ofSize: 13, weight: .semibold)
        nameButton.contentTintColor = .labelColor
        (nameButton.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        nameButton.setAccessibilityIdentifier("bato-space-header")
        nameButton.setAccessibilityLabel("Pinned tabs of \(name)")
        nameButton.setAccessibilityValue(collapsed ? "collapsed" : "expanded")
        nameButton.setAccessibilityHelp("Shows or hides the pinned tabs and folders of this Space.")
        actions.image = sidebarSymbol("ellipsis", size: 13, weight: .semibold)
        actions.imagePosition = .imageOnly
        actions.isBordered = false
        actions.bezelStyle = .recessed
        actions.focusRingType = .none
        actions.contentTintColor = NSColor.labelColor.withAlphaComponent(0.7)
        actions.alphaValue = 0
        actions.setAccessibilityLabel("Space actions")
        actions.setAccessibilityIdentifier("bato-space-header-actions")
        actions.toolTip = "Rename, recolour or add a folder to this Space"
        for view in [nameButton, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            nameButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.labelX),
            nameButton.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -2),
            nameButton.topAnchor.constraint(equalTo: topAnchor),
            nameButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
            actions.widthAnchor.constraint(equalToConstant: 24),
            actions.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        isCollapsed = collapsed
        nameButton.setAccessibilityValue(collapsed ? "collapsed" : "expanded")
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SidebarMetrics.pinsAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().chevronTurn = collapsed ? 1 : 0
            }
        } else {
            chevronTurn = collapsed ? 1 : 0
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A header rebuilt under a resting pointer never gets a mouseEntered.
        guard let window else { return }
        hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { toggle?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            SidebarStyle.headerHoverFill.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: SidebarMetrics.cornerRadius,
                         yRadius: SidebarMetrics.cornerRadius).fill()
        }
        let slot = NSPoint(x: 18, y: bounds.midY)
        if hovered || isCollapsed || chevronTurn != 0 {
            drawChevron(at: slot)
        } else if let icon, let image = CreateSpacePageView.iconImage(icon, size: 14) {
            drawIcon(image, at: slot)
        } else {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: slot.x - 6, y: slot.y - 6, width: 12, height: 12)).fill()
        }
    }

    /// Emoji keep their colours; symbols take the Space colour.
    private func drawIcon(_ image: NSImage, at slot: NSPoint) {
        let rect = NSRect(x: slot.x - 7, y: slot.y - 7, width: 14, height: 14)
        guard image.isTemplate else { return image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            image.draw(in: bounds)
            SidebarStyle.vivid(self.color).setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// A 10pt wide chevron, stroke 1.5, turned about its centre by `chevronTurn` quarter-turns.
    private func drawChevron(at centre: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -5, y: 2.5))
        path.line(to: NSPoint(x: 0, y: -2.5))
        path.line(to: NSPoint(x: 5, y: 2.5))
        var transform = AffineTransform(translationByX: centre.x, byY: centre.y)
        transform.rotate(byRadians: .pi / 2 * chevronTurn)
        path.transform(using: transform)
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.labelColor.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}

/// The "Tidy | Clear" row above New Tab. Labels are dim until the pointer rests on one.
@MainActor
private final class TidyClearRow: NSView {
    private lazy var tidyButton = ActionButton(title: "Tidy") { [weak self] in self?.tidy?() }
    private lazy var clearButton = ActionButton(title: "Clear") { [weak self] in self?.clear?() }
    private let separator = NSView()
    private var hoveredLabel: NSButton? { didSet { if hoveredLabel !== oldValue { styleLabels() } } }
    private var tracking: NSTrackingArea?
    var tidy: (() -> Void)?
    var clear: (() -> Void)?
    private let canTidy: Bool
    private let canClear: Bool

    init(canTidy: Bool, canClear: Bool) {
        self.canTidy = canTidy
        self.canClear = canClear
        super.init(frame: .zero)
        tidyButton.image = sidebarSymbol("paintbrush.pointed", size: 11, weight: .semibold)
        tidyButton.imagePosition = .imageLeading
        tidyButton.toolTip = "Archive duplicate Today tabs"
        tidyButton.setAccessibilityIdentifier("bato-tidy")
        tidyButton.setAccessibilityLabel("Tidy")
        tidyButton.setAccessibilityHelp("Archives Today tabs that repeat another tab's address. Archived tabs can be restored.")
        clearButton.toolTip = "Clear unselected Today tabs"
        clearButton.setAccessibilityIdentifier("bato-clear")
        clearButton.setAccessibilityLabel("Clear")
        clearButton.setAccessibilityHelp("Archives every Today tab except the selected one. Archived tabs can be restored.")
        tidyButton.isEnabled = canTidy
        clearButton.isEnabled = canClear
        for button in [tidyButton, clearButton] {
            button.isBordered = false
            button.bezelStyle = .recessed
            button.focusRingType = .none
        }
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor
        let stack = NSStackView(views: [tidyButton, separator, clearButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        styleLabels()
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    private func styleLabels() {
        for button in [tidyButton, clearButton] {
            let alpha: CGFloat = button === hoveredLabel ? 0.95 : (hoveredLabel == nil ? 0.35 : 0.25)
            let color = NSColor.labelColor.withAlphaComponent(button.isEnabled ? alpha : 0.2)
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: color])
            button.contentTintColor = color
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoveredLabel = [tidyButton, clearButton].first { $0.isEnabled && $0.frame.insetBy(dx: -4, dy: -6).contains(convert(point, to: $0.superview)) }
    }
    override func mouseExited(with event: NSEvent) { hoveredLabel = nil }
}

/// A box that clips a picture of the pinned section to its own height, picture pinned to the top.
@MainActor
private final class PinnedClipView: NSView {
    let picture: NSImageView
    override var isFlipped: Bool { true }
    init(image: NSImage, offsetY: CGFloat, size: NSSize) {
        picture = NSImageView(frame: NSRect(x: 0, y: offsetY, width: size.width, height: size.height))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        picture.image = image
        picture.imageScaling = .scaleNone
        addSubview(picture)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
}
