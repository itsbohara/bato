import AppKit
import BatoCore
import BatoRuntime
import BatoBrowserUI
import BatoBlocking

private typealias CreatePage = @convention(c) (UInt64, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32) -> Int32
private typealias CommandID = @convention(c) (Int32) -> Int32
private typealias ScheduleSelection = @convention(c) (UInt64) -> Void
private typealias SidebarGeometry = @convention(c) (UInt64, Int32, Int32) -> Int32
private typealias PresentSplit = @convention(c) (UInt64, Int32, Int32, Int32, Double) -> Int32
private typealias ActivePage = @convention(c) (UInt64) -> Int32
private typealias PageAction = @convention(c) (UInt64, Int32) -> Int32
private typealias PresentPeek = @convention(c) (UInt64, Int32, Int32) -> UInt64
private typealias EndPeek = @convention(c) (UInt64, UInt64, Int32) -> Int32
private typealias NavigatePage = @convention(c) (UInt64, Int32, UnsafePointer<CChar>?) -> Int32
private typealias OpenProfileWindow = @convention(c) (UnsafePointer<CChar>?, Int32) -> Int32
private typealias DeleteProfileData = @convention(c) (UnsafePointer<CChar>?) -> Int32
private typealias DownloadSnapshot = @convention(c) () -> Int32
private typealias DownloadAct = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32) -> Int32
@MainActor private var workspaceDirectory: URL?
@MainActor private var createPage: CreatePage?
@MainActor private var selectPage: PageAction?
@MainActor private var closePage: PageAction?
@MainActor private var activePage: ActivePage?
@MainActor private var nativeFocus: ActivePage?
@MainActor private var commandID: CommandID?
@MainActor private var scheduleSelection: ScheduleSelection?
@MainActor private var sidebarGeometry: SidebarGeometry?
@MainActor private var pageFocus: ActivePage?
@MainActor private var presentSplitPages: PresentSplit?
@MainActor private var separateSplitPages: ActivePage?
@MainActor private var presentPeekPages: PresentPeek?
@MainActor private var endPeekPages: EndPeek?
@MainActor private var navigatePage: NavigatePage?
@MainActor private var openProfileWindow: OpenProfileWindow?
@MainActor private var deleteProfileData: DeleteProfileData?
@MainActor private var downloadSnapshot: DownloadSnapshot?
@MainActor private var downloadAct: DownloadAct?
@MainActor private var setPageMuted: (@convention(c) (Int32, Int32) -> Int32)?
@MainActor private var nativeDownloads: NativeDownloadsEngine?
@MainActor private var downloadsController: DownloadsController?
@MainActor private var workspaceSlots: [UInt64: WorkspaceSlot] = [:]

/// Download events and actions through the client's engine tables. The client has already mapped
/// engine Profile keys to Bato Profile UUID strings in both directions.
@MainActor private final class NativeDownloadsEngine: DownloadsEngine {
    var onEvent: ((DownloadEvent) -> Void)?
    func requestSnapshot() { _ = downloadSnapshot?() }
    func perform(_ action: DownloadAction, id: String, profileKey: String) -> Bool {
        downloadAct?(profileKey, id, action.engineCode) == 1
    }
}

/// Routes pages to one Chromium window per Bato Profile: a Chrome Browser has exactly one
/// Profile, so pages of different Profiles can never share a window. The launch Profile
/// keeps the original window and context; every other Profile gets its own context and
/// window on its first page, which stays pending until that window's anchor is bound.
@MainActor private final class WorkspaceEngine: PageEngine {
    let launchProfileID: UUID
    /// Window token per Profile that currently has a bound window.
    private(set) var windows: [UUID: UInt64] = [:]
    var pages: [Int32: LivePage] = [:]
    /// Previews are never organization pages: they stay here until promoted or terminal.
    var transient: [Int32: LivePage] = [:]
    var peek: (generation: UInt64, parent: Int32, preview: Int32)?
    var onEvent: ((PageEvent) -> Void)?
    var onAnchorLost: (() -> Void)?
    /// Called with the token whose window should carry the sidebar and be in front.
    var onShow: ((UInt64) -> Void)?
    var onWindowReady: (() -> Void)?
    private var currentProfileID: UUID
    private var pending: [UUID: [(page: LivePage, url: URL)]] = [:]
    private var windowRequest: UUID?
    private var windowQueue: [UUID] = []
    init(token: UInt64, profileID: UUID) {
        launchProfileID = profileID
        currentProfileID = profileID
        windows[profileID] = token
    }
    var supportedProfileIDs: Set<UUID> { [launchProfileID] }
    func supportsProfile(_ id: UUID) -> Bool { id == launchProfileID || openProfileWindow != nil }
    func activateProfile(_ id: UUID) { currentProfileID = id }
    func requestWindowIfMissing(for profileID: UUID) -> Bool {
        guard windows[profileID] == nil, supportsProfile(profileID) else { return false }
        return requestWindow(for: profileID)
    }
    func token(forProfile id: UUID) -> UInt64? { windows[id] }
    func isCurrentWindow(_ token: UInt64) -> Bool { windows[currentProfileID] == token }

    func create(_ page: LivePage, url: URL) -> Bool {
        guard supportsProfile(page.profileID) else { return false }
        if let token = windows[page.profileID] { return createNow(token, page, url) }
        guard requestWindow(for: page.profileID) else { return false }
        pending[page.profileID, default: []].append((page, url))
        return true
    }
    /// The client refuses a window whose context is not this Profile's, so a page can never run in another Profile's storage.
    private func createTab(_ token: UInt64, profileID: UUID, url: URL) -> Int32 {
        url.absoluteString.withCString { address in
            profileID.uuidString.withCString { key in
                createPage?(token, address, key, profileID == launchProfileID ? 1 : 0) ?? 0
            }
        }
    }
    private func createNow(_ token: UInt64, _ page: LivePage, _ url: URL) -> Bool {
        let id = createTab(token, profileID: page.profileID, url: url)
        guard id > 0, pages[id] == nil else { return false }
        pages[id] = page
        return true
    }
    private func requestWindow(for profileID: UUID) -> Bool {
        if windowRequest == profileID || windowQueue.contains(profileID) { return true }
        guard windowRequest == nil else {
            windowQueue.append(profileID)
            return true
        }
        return startWindowRequest(profileID)
    }
    private func startWindowRequest(_ profileID: UUID) -> Bool {
        windowRequest = profileID
        let accepted = profileID.uuidString.withCString {
            openProfileWindow?($0, profileID == launchProfileID ? 1 : 0) == 1
        }
        if !accepted { windowRequest = nil }
        return accepted
    }
    /// The requested window's anchor is bound (token set) or the request failed (token nil).
    func windowRequestFinished(profileID: UUID, token: UInt64?) {
        guard windowRequest == profileID else { return }
        windowRequest = nil
        let waiting = pending.removeValue(forKey: profileID) ?? []
        if let token {
            windows[profileID] = token
            for (page, url) in waiting where !createNow(token, page, url) { onEvent?(.creationFailed(page)) }
        } else {
            for (page, _) in waiting { onEvent?(.creationFailed(page)) }
        }
        while windowRequest == nil, !windowQueue.isEmpty {
            let next = windowQueue.removeFirst()
            if !startWindowRequest(next) {
                for (page, _) in pending.removeValue(forKey: next) ?? [] { onEvent?(.creationFailed(page)) }
            }
        }
        // Pages are live now, so the committed selection can be presented in the new window.
        if token != nil { onWindowReady?() }
    }
    /// Asks the engine to close this Profile's windows and destroy its storage. The window's later
    /// detach finds no Profile and is ignored; the pages are gone from the engine's tables at once.
    func destroyProfile(_ id: UUID) -> Bool {
        guard id != launchProfileID, let destroy = deleteProfileData,
              id.uuidString.withCString({ destroy($0) }) == 1 else { return false }
        windows.removeValue(forKey: id)
        pending.removeValue(forKey: id)
        windowQueue.removeAll { $0 == id }
        for (key, page) in pages where page.profileID == id { pages.removeValue(forKey: key) }
        for (key, page) in transient where page.profileID == id { transient.removeValue(forKey: key) }
        return true
    }
    /// A closed window takes its pages with it; their saved entries stay in organization.
    func windowDetached(_ token: UInt64) {
        guard let profileID = windows.first(where: { $0.value == token })?.key else { return }
        windows.removeValue(forKey: profileID)
        let lost = pages.filter { $0.value.profileID == profileID }
        for id in lost.keys { pages.removeValue(forKey: id) }
        for (id, page) in transient where page.profileID == profileID { transient.removeValue(forKey: id) }
        if lost.isEmpty { return }
        peek = nil
        DispatchQueue.main.async { [weak self] in
            for page in lost.values { self?.onEvent?(.unloaded(page)) }
        }
    }

    func select(_ page: LivePage?) {
        let profileID = page?.profileID ?? currentProfileID
        guard let token = windows[profileID] ?? (page == nil ? windows[launchProfileID] ?? windows.values.first : nil) else { return }
        onShow?(token)
        let id: Int32
        if let page {
            guard let found = pages.first(where: { $0.value == page }) else {
                _ = selectPage?(token, 0)
                return
            }
            id = found.key
        } else { id = 0 }
        _ = selectPage?(token, id)
    }
    var supportsSplits: Bool { presentSplitPages != nil && separateSplitPages != nil }
    func presentSplit(left: LivePage, right: LivePage, focused: LivePage, ratio: Double) -> Bool {
        guard left.profileID == right.profileID, let token = windows[left.profileID],
              let a = pages.first(where: { $0.value == left })?.key,
              let b = pages.first(where: { $0.value == right })?.key,
              let f = pages.first(where: { $0.value == focused })?.key else { return false }
        onShow?(token)
        return presentSplitPages?(token, a, b, f, ratio) == 1
    }
    func separateSplit() -> Bool {
        guard let token = windows[currentProfileID] else { return true }
        return separateSplitPages?(token) == 1
    }
    var supportsPeek: Bool { presentPeekPages != nil && endPeekPages != nil }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool {
        guard peek == nil, parent.profileID == preview.profileID, let token = windows[preview.profileID],
              let parentID = pages.first(where: { $0.value == parent })?.key else { return false }
        let id = createTab(token, profileID: preview.profileID, url: url)
        guard id > 0, pages[id] == nil, transient[id] == nil else { return false }
        transient[id] = preview
        let generation = presentPeekPages?(token, parentID, id) ?? 0
        guard generation != 0 else {
            _ = selectPage?(token, parentID)
            _ = closePage?(token, id)
            return false
        }
        peek = (generation, parentID, id)
        peekToken = token
        return true
    }
    private var peekToken: UInt64?
    func endPeek(restoreParent: Bool) -> PeekEndResult {
        guard let current = peek, let token = peekToken else { return .stale }
        switch endPeekPages?(token, current.generation, restoreParent ? 1 : 0) {
        case 1: peek = nil; return .ended
        case 2: peek = nil; return .parentRestoreFailed
        default: return .stale
        }
    }
    var supportsNavigation: Bool { navigatePage != nil }
    /// Organization pages only: a transient preview is never a navigation target.
    func perform(_ command: PageNavigationCommand, on page: LivePage) -> Bool {
        guard let id = pages.first(where: { $0.value == page })?.key, let token = windows[page.profileID],
              let navigatePage else { return false }
        switch command {
        case .load(let url): return url.absoluteString.withCString { navigatePage(token, id, $0) } == 1
        }
    }
    func adoptPeekPreview(_ preview: LivePage) {
        guard let id = transient.first(where: { $0.value == preview })?.key else { return }
        transient.removeValue(forKey: id)
        pages[id] = preview
    }
    func requestClose(_ page: LivePage) {
        if let index = pending[page.profileID]?.firstIndex(where: { $0.page == page }) {
            pending[page.profileID]?.remove(at: index)
            DispatchQueue.main.async { [weak self] in self?.onEvent?(.closed(page)) }
            return
        }
        guard let id = (pages.first(where: { $0.value == page }) ?? transient.first(where: { $0.value == page }))?.key,
              let token = windows[page.profileID] else { return }
        if closePage?(token, id) != 1 { onEvent?(.closeCancelled(page)) }
    }
    func receive(token: UInt64, id: Int32, kind: Int32, url: String, title: String) {
        // Only the window of the selected workspace's Profile may clear or restart the selection:
        // another Profile's window showing its blank anchor says nothing about it.
        if kind == 5 || kind == 7 { if isCurrentWindow(token) { onAnchorLost?() }; return }
        if kind == 6 && id == 0 { if isCurrentWindow(token) { onEvent?(.selectionCleared) }; return }
        guard let page = pages[id] ?? transient[id] else { return }
        switch kind {
        case 6: if transient[id] == nil { onEvent?(.selected(page)) }
        case 1:
            guard let address = URL(string: url) else { return }
            onEvent?(.navigation(page, url: address, title: title))
        case 2:
            pages.removeValue(forKey: id)
            transient.removeValue(forKey: id)
            TabAudioCenter.shared.update(entryID: page.entryID, audible: false, muted: false)
            onEvent?(.closed(page))
        case 3: onEvent?(.closeCancelled(page))
        case 4:
            pages.removeValue(forKey: id)
            transient.removeValue(forKey: id)
            TabAudioCenter.shared.update(entryID: page.entryID, audible: false, muted: false)
            onEvent?(.unloaded(page))
        default: break
        }
    }
}

/// This root stays visible as a six-point edge in hidden mode. Chromium owns
/// its bounds; the client never creates a second window or covers the whole page.
@MainActor private final class AttachedWorkspaceRoot: NSView {
    var onAttach: (() -> Void)?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?
    weak var content: NSView? { didSet { needsLayout = true } }
    var mode: Int32 = 1 {
        didSet {
            content?.isHidden = mode == 0
            grip.isHidden = mode == 0 || content == nil
            needsLayout = true
        }
    }
    private var area: NSTrackingArea?
    private let grip = SidebarResizeGrip(frame: .zero)
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(grip)
        grip.onResize = { [weak self] width in self?.onResize?(width) }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func layout() {
        super.layout()
        content?.isHidden = mode == 0
        grip.isHidden = mode == 0 || content == nil
        content?.frame = NSRect(x: 0, y: 0, width: max(214, bounds.width), height: bounds.height)
        grip.frame = NSRect(x: max(0, bounds.width - 6), y: 0, width: 6, height: bounds.height)
    }
    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        area = tracking
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.onAttach?()
        }
    }
}

@MainActor private final class SidebarResizeGrip: NSView {
    var onResize: ((CGFloat) -> Void)?
    private var dragOrigin: CGFloat?
    private var startWidth: CGFloat = 260
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Sidebar width")
        setAccessibilityIdentifier("bato-sidebar-resize")
        toolTip = "Drag to resize sidebar; arrow keys change width"
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Widen sidebar") { [weak self] in self?.adjust(20); return self != nil },
            NSAccessibilityCustomAction(name: "Narrow sidebar") { [weak self] in self?.adjust(-20); return self != nil }
        ])
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with event: NSEvent) {
        guard let root = superview else { return }
        window?.makeFirstResponder(self)
        dragOrigin = root.convert(event.locationInWindow, from: nil).x
        startWidth = root.bounds.width
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let root = superview else { return }
        onResize?(startWidth + root.convert(event.locationInWindow, from: nil).x - origin)
    }
    override func mouseUp(with event: NSEvent) { dragOrigin = nil }
    private func adjust(_ delta: CGFloat) { onResize?((superview?.bounds.width ?? 260) + delta) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 { adjust(-10) }
        else if event.keyCode == 124 { adjust(10) }
        else { super.keyDown(with: event) }
    }
}

/// State shared by every window slot: one organization, one controller and one engine.
/// The sidebar lives in exactly one window at a time and follows the selected page.
@MainActor private final class WorkspaceHost {
    var controller: NativeWorkspaceController?
    var engine: WorkspaceEngine?
    var router: WorkspaceKeyRouter?
    var primaryCreated = false
    weak var mounted: WorkspaceSlot?

    func mount(_ slot: WorkspaceSlot) {
        guard mounted !== slot, let content = controller?.root else { return }
        mounted?.root.content = nil
        content.removeFromSuperview()
        slot.root.content = content
        slot.root.addSubview(content, positioned: .below, relativeTo: nil)
        mounted = slot
        router?.retarget(token: slot.token, root: slot.root)
    }
}

@MainActor private let workspaceHost = WorkspaceHost()

@MainActor private final class WorkspaceSlot {
    let root = AttachedWorkspaceRoot(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
    var controller: NativeWorkspaceController? { workspaceHost.controller }
    var engine: WorkspaceEngine? { workspaceHost.engine }
    private var blockingControls: BlockingControls?
    private var cardFrame: ContentCardFrameView?
    private var width: Int32 = 260
    private var mode: Int32 = 1
    private var pointerMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var keyObserver: NSObjectProtocol?
    private var menuTracking = false
    private var changingGeometry = false
    /// Fullscreen only: the sidebar floats over the page. `mode` is untouched so leaving fullscreen
    /// restores the docked or hidden sidebar the user had.
    private var fullscreenRevealed = false
    private var fullscreenObservers: [NSObjectProtocol] = []
    private var resignObserver: NSObjectProtocol?
    /// Runs while the sidebar floats: a reveal that did not come from the pointer (Cmd-T, menus, focus
    /// restoration) never gets a `mouseExited`, so without this it stays over the page.
    private var peekPoll: Timer?
    /// The floating sidebar was revealed by `focusNative`, not by the pointer.
    private var revealedByFocusRequest = false
    let token: UInt64
    /// The first slot owns organization; later slots are windows of other Profiles that borrow its sidebar.
    init(token: UInt64, directory: URL?) {
        self.token = token
        root.onEnter = { [weak self] in self?.reveal() }
        root.onExit = { [weak self] in self?.dismissPeek(on: .pointerExited) }
        root.onResize = { [weak self] width in
            guard let self else { return }
            _ = self.setGeometry(width: Int32(min(400, max(220, width.rounded()))), mode: self.mode)
        }
        root.onAttach = { [weak self] in self?.attached() }
        guard let directory else { return }
        do {
            let controller = try NativeWorkspaceController(directory: directory, handlesKeyEquivalents: false) { profileID in
                let engine = WorkspaceEngine(token: token, profileID: profileID)
                workspaceHost.engine = engine
                return engine
            }
            workspaceHost.controller = controller
            if downloadsController == nil, downloadSnapshot != nil, downloadAct != nil {
                let engine = NativeDownloadsEngine()
                let downloads = DownloadsController(engine: engine)
                nativeDownloads = engine
                downloadsController = downloads
                controller.attachDownloads(downloads)
            }
            controller.requestNativeFocus = { workspaceHost.mounted?.focusNative() }
            controller.requestSidebarToggle = { _ = workspaceHost.mounted?.toggle() }
            controller.requestPagePresentation = {
                if let token = workspaceHost.mounted?.token { scheduleSelection?(token) }
            }
            engine?.onEvent = { [weak controller] event in controller?.receive(event) }
            engine?.onAnchorLost = { [weak controller] in _ = controller?.runtime.start() }
            engine?.onWindowReady = { [weak controller] in _ = controller?.runtime.start() }
            engine?.onShow = { token in workspaceSlots[token]?.show() }
            root.content = controller.root
            root.addSubview(controller.root, positioned: .below, relativeTo: nil)
            root.needsLayout = true
            workspaceHost.mounted = self
            let router = WorkspaceKeyRouter(token: token, root: root,
                                            toggle: { workspaceHost.mounted?.toggle() ?? false },
                                            dismissPeek: { [weak controller] in
                guard let controller, let preview = controller.runtime.peekSession.preview,
                      !preview.isPendingDismissal else { return false }
                controller.dismissPeek()
                return true
            }, promotePeek: { [weak controller] in
                guard let controller, let preview = controller.runtime.peekSession.preview,
                      !preview.isPendingDismissal else { return false }
                controller.promotePeek()
                return true
            }, editAddress: { [weak controller] in controller?.editAddress() ?? false },
               copyLink: { [weak controller] in controller?.copyCurrentLink() ?? false },
               pageItems: { [weak self] in self?.blockingMenuItems() ?? [] })
            workspaceHost.router = router
        } catch {
            let message = NSTextField(wrappingLabelWithString: NativeWorkspaceController.unavailableMessage(for: error))
            message.frame = NSRect(x: 14, y: 24, width: 232, height: 130)
            root.addSubview(message)
        }
    }
    /// Keeps the tinted card gutter above Chrome's views and in step with the sidebar reservation.
    /// Fullscreen has no card: the page fills the screen.
    private func updateCard() {
        guard let content = root.window?.contentView else { return }
        guard let card = cardFrame ?? workspaceHost.controller?.makeCardFrame() else { return }
        cardFrame = card
        if card.superview !== content {
            card.frame = content.bounds
            content.addSubview(card, positioned: .above, relativeTo: nil)
        } else if content.subviews.last !== card {
            content.addSubview(card, positioned: .above, relativeTo: nil)
        }
        card.isCardShown = !isFullscreen
        card.sidebarCoverWidth = mode == 0 ? 0 : CGFloat(width)
        card.sidebarWidth = mode == 1 ? CGFloat(min(width, Int32(max(0, content.bounds.width - 320)))) : 0
    }
    private func attached() {
        installPointerMonitor()
        updateCard()
        if fullscreenObservers.isEmpty, let window = root.window {
            for (name, entering) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
                fullscreenObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.fullscreenRevealed = false
                        self.root.mode = entering ? 0 : self.mode
                        self.syncPeekPoll()
                        self.root.layoutSubtreeIfNeeded()
                        self.updateCard()
                    }
                })
            }
        }
        if resignObserver == nil, let window = root.window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissPeek(on: .windowResigned) }
            }
        }
        if keyObserver == nil, let window = root.window {
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameKey() }
            }
        }
        if workspaceHost.mounted === self {
            workspaceHost.controller?.start()
            workspaceHost.router?.retarget(token: token, root: root)
            workspaceHost.router?.install()
        }
    }
    /// Carries the sidebar to the focused window and adopts that window's visible page as the selection.
    private func becameKey() {
        workspaceHost.mount(self)
        guard let engine, let controller, let id = activePage?(token), id > 0,
              let page = engine.pages[id] else { return }
        controller.receive(.selected(page))
    }
    /// Brings this window forward with the sidebar, e.g. when a page of its Profile is selected.
    func show() {
        workspaceHost.mount(self)
        if NSApp.isActive, let window = root.window, !window.isKeyWindow, window.attachedSheet == nil {
            window.makeKeyAndOrderFront(nil)
        }
    }
    func focusNative() {
        if mode == 0 {
            guard setGeometry(mode: 2) else { return }
            revealedByFocusRequest = true
        }
        _ = nativeFocus?(token)
    }
    /// Empty until the host has started blocking: the Page menu is built once, when the root attaches.
    private func blockingMenuItems() -> [NSMenuItem] {
        guard BlockingHost.shared.profiles != nil else { return [] }
        let controls = BlockingControls(serviceForProfile: { BlockingHost.shared.service(forProfile: $0) }, activePage: { [weak self] in
            guard let self, let controller = self.controller, let engine = self.engine,
                  let entryID = controller.runtime.state.currentWorkspace.activeEntryID,
                  let url = controller.runtime.state.visibleEntries.first(where: { $0.id == entryID })?.lastURL,
                  let (id, page) = engine.pages.first(where: { $0.value.entryID == entryID }) else { return nil }
            return BlockingControls.ActivePage(url: url, browserID: id, profileKey: page.profileID.uuidString)
        }, reload: { [weak self] id in
            guard let self, let page = self.engine?.pages[id],
                  let url = self.controller?.runtime.state.visibleEntries.first(where: { $0.id == page.entryID })?.lastURL else { return }
            _ = self.engine?.perform(.load(url), on: page)
        })
        blockingControls = controls
        return controls.menuItems()
    }
    private var canInteract: Bool {
        guard NSApp.isActive, let window = root.window else { return false }
        return window.isKeyWindow && window.attachedSheet == nil && NSApp.modalWindow == nil
    }
    @discardableResult private func setGeometry(width requested: Int32? = nil, mode next: Int32,
                                                requiresKey: Bool = true) -> Bool {
        guard !requiresKey || canInteract, !changingGeometry else { return false }
        changingGeometry = true
        defer { changingGeometry = false }
        guard sidebarGeometry?(token, requested ?? width, next) == 1 else { return false }
        width = requested ?? width
        revealedByFocusRequest = false
        mode = next
        root.mode = next
        root.layoutSubtreeIfNeeded()
        updateCard()
        syncPeekPoll()
        return true
    }
    private var isFullscreen: Bool { root.window?.styleMask.contains(.fullScreen) == true }
    @discardableResult private func setFullscreenReveal(_ revealed: Bool, requiresKey: Bool = true) -> Bool {
        guard !requiresKey || canInteract, !changingGeometry else { return false }
        changingGeometry = true
        defer { changingGeometry = false }
        guard sidebarGeometry?(token, width, revealed ? 2 : 0) == 1 else { return false }
        fullscreenRevealed = revealed
        revealedByFocusRequest = false
        root.mode = revealed ? 2 : 0
        root.layoutSubtreeIfNeeded()
        syncPeekPoll()
        return true
    }
    @discardableResult func toggle() -> Bool {
        if isFullscreen { return setFullscreenReveal(!fullscreenRevealed) }
        guard setGeometry(mode: mode == 1 ? 0 : 1) else { return false }
        if mode == 0 { _ = pageFocus?(token) }
        return true
    }
    private func reveal() {
        if isFullscreen {
            if !fullscreenRevealed, canInteract, !menuTracking { setFullscreenReveal(true) }
            return
        }
        guard mode == 0, canInteract, !menuTracking else { return }
        _ = setGeometry(mode: 2) // Hover never steals focus from the page.
    }
    private var sidebarHasFocus: Bool {
        guard let focused = root.window?.firstResponder as? NSView else { return false }
        return focused === root || focused.isDescendant(of: root)
    }
    private var isFloating: Bool { isFullscreen ? fullscreenRevealed : mode == 2 }
    private var pointerInsideSidebar: Bool {
        guard let window = root.window else { return false }
        return root.bounds.contains(root.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }
    private func dismissPeek(on event: SidebarPeekDismissal.Event) {
        guard isFloating, let window = root.window else { return }
        let incidental = revealedByFocusRequest && window.firstResponder === controller?.focusTarget
        let context = SidebarPeekDismissal.Context(
            pointerInside: pointerInsideSidebar, sidebarFocused: sidebarHasFocus, focusIsIncidental: incidental,
            interactive: window.attachedSheet == nil && NSApp.modalWindow == nil && !menuTracking)
        guard SidebarPeekDismissal.shouldDismiss(on: event, context) else { return }
        let requiresKey = event != .windowResigned
        let hidden = isFullscreen ? setFullscreenReveal(false, requiresKey: requiresKey)
                                  : setGeometry(mode: 0, requiresKey: requiresKey)
        // Focus would otherwise stay on the hidden sidebar.
        if hidden, event == .pageClicked || incidental { _ = pageFocus?(token) }
    }
    private func syncPeekPoll() {
        guard isFloating else {
            peekPoll?.invalidate()
            peekPoll = nil
            return
        }
        guard peekPoll == nil else { return }
        peekPoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPeek(on: .pointerPoll) }
        }
    }
    private func installPointerMonitor() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.root.window else { return event }
                if event.type == .keyDown {
                    // Command chords (Cmd-S, Cmd-T) are handled by their own commands.
                    if !event.modifierFlags.contains(.command), !self.sidebarHasFocus { self.dismissPeek(on: .pageKey) }
                } else if !self.root.bounds.contains(self.root.convert(event.locationInWindow, from: nil)) {
                    self.dismissPeek(on: .pageClicked)
                }
                return event // Preserve the original page event.
            }
        }
        for (name, tracking) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTracking = tracking }
            })
        }
    }
    func detach() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        peekPoll?.invalidate()
        peekPoll = nil
        for observer in menuObservers + fullscreenObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll()
        fullscreenObservers.removeAll()
        root.onEnter = nil
        root.onExit = nil
        root.onResize = nil
        root.onAttach = nil
    }

}

@_cdecl("BatoSwiftWorkspaceConfigure")
@MainActor public func configureWorkspace(_ directory: UnsafePointer<CChar>?,
    _ create: @escaping @convention(c) (UInt64, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32) -> Int32,
    _ select: @escaping @convention(c) (UInt64, Int32) -> Int32,
    _ close: @escaping @convention(c) (UInt64, Int32) -> Int32,
    _ active: @escaping @convention(c) (UInt64) -> Int32,
    _ focus: @escaping @convention(c) (UInt64) -> Int32,
    _ command: @escaping @convention(c) (Int32) -> Int32,
    _ schedule: @escaping @convention(c) (UInt64) -> Void,
    _ geometry: @escaping @convention(c) (UInt64, Int32, Int32) -> Int32,
    _ focusPage: @escaping @convention(c) (UInt64) -> Int32) {
    precondition(Thread.isMainThread)
    guard let directory else { return }
    let path = String(cString: directory)
    guard path.hasPrefix("/"), workspaceDirectory == nil else { return }
    workspaceDirectory = URL(fileURLWithPath: path, isDirectory: true)
    createPage = create
    selectPage = select
    closePage = close
    activePage = active
    nativeFocus = focus
    commandID = command
    scheduleSelection = schedule
    sidebarGeometry = geometry
    pageFocus = focusPage
}

@MainActor func workspaceModeEnabled() -> Bool { workspaceDirectory != nil }

/// The client only offers windows it requested for a Profile; the first one owns organization.
@MainActor func createWorkspaceSlot(_ token: UInt64) -> UnsafeMutableRawPointer? {
    guard let directory = workspaceDirectory else { return nil }
    let primary = !workspaceHost.primaryCreated
    if !primary && workspaceHost.controller == nil { return nil }
    workspaceHost.primaryCreated = true
    let slot = WorkspaceSlot(token: token, directory: primary ? directory : nil)
    workspaceSlots[token] = slot
    return Unmanaged.passUnretained(slot.root).toOpaque()
}
@MainActor func focusWorkspaceSlot(_ token: UInt64) -> UnsafeMutableRawPointer? {
    guard let slot = workspaceSlots[token] else { return nil }
    let sidebar = workspaceHost.mounted === slot ? slot.controller?.focusTarget : nil
    return Unmanaged.passUnretained(sidebar ?? slot.root).toOpaque()
}
@MainActor func detachWorkspaceSlot(_ token: UInt64) {
    guard let slot = workspaceSlots.removeValue(forKey: token) else { return }
    slot.detach()
    workspaceHost.engine?.windowDetached(token)
    guard workspaceHost.mounted === slot || workspaceHost.mounted == nil else { return }
    if let next = workspaceSlots.values.first {
        workspaceHost.mount(next)
    } else {
        workspaceHost.controller?.prepareForQuit()
        workspaceHost.router?.restore()
    }
}

@_cdecl("BatoSwiftWorkspacePageEvent")
@MainActor public func workspacePageEvent(_ token: UInt64, _ browserID: Int32, _ kind: Int32,
                                        _ url: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?) {
    precondition(Thread.isMainThread)
    workspaceHost.engine?.receive(token: token, id: browserID, kind: kind,
        url: url.map { String(cString: $0) } ?? "", title: title.map { String(cString: $0) } ?? "")
}

/// Chromium's application delegate opens links that macOS hands the app (Bato as the default browser)
/// as a tab in its own tab strip, which Bato does not track. Web links go to the Bato workspace
/// instead; anything else keeps Chromium's behaviour. The hook is installed before the workspace
/// exists, so links that start the app, or arrive while a sheet is open, wait here until the
/// workspace can take them.
@MainActor private enum ExternalURLRouter {
    private static var installed = false
    private static var pending: [URL] = []
    private static var retry: Timer?
    private static let patience = 60

    static func install() {
        guard !installed, let delegateClass = NSClassFromString("AppController") else { return }
        let selector = NSSelectorFromString("application:openURLs:")
        guard let method = class_getInstanceMethod(delegateClass, selector) else {
            fputs("{\"event\":\"external-url-routing-unavailable\"}\n", stderr)
            return
        }
        installed = true
        let chromium = method_getImplementation(method)
        let route: @convention(block) (AnyObject, AnyObject, NSArray) -> Void = { object, application, urls in
            let links = urls.compactMap { $0 as? URL }
            if MainActor.assumeIsolated({ accept(links) }) { return }
            typealias Original = @convention(c) (AnyObject, Selector, AnyObject, NSArray) -> Void
            unsafeBitCast(chromium, to: Original.self)(object, selector, application, urls)
        }
        method_setImplementation(method, imp_implementationWithBlock(route))
        fputs("{\"event\":\"external-url-routing-installed\"}\n", stderr)
    }

    /// Takes plain web links now or queues them. Anything else is left to Chromium.
    private static func accept(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, urls.allSatisfy(NativeWorkspaceController.isExternalWebLink) else { return false }
        pending += urls
        deliver()
        if !pending.isEmpty { waitForWorkspace() }
        return true
    }

    private static func deliver() {
        guard let controller = workspaceHost.controller else { return }
        let requested = pending.count
        pending.removeAll { controller.openExternalURL($0) }
        fputs("{\"event\":\"external-url-routed\",\"requested\":\(requested),\"opened\":\(requested - pending.count)}\n", stderr)
    }

    private static func waitForWorkspace() {
        guard retry == nil else { return }
        var attempts = 0
        retry = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            MainActor.assumeIsolated {
                attempts += 1
                if !pending.isEmpty { deliver() }
                if pending.isEmpty || attempts >= patience {
                    if !pending.isEmpty { fputs("{\"event\":\"external-url-dropped\",\"count\":\(pending.count)}\n", stderr) }
                    pending.removeAll()
                    timer.invalidate()
                    retry = nil
                }
            }
        }
    }
}

/// Called from the client's registration, before the application runs, so links that launch the app are seen.
@_cdecl("BatoSwiftInstallExternalURLRouter")
@MainActor public func installExternalURLRouter() {
    ExternalURLRouter.install()
}

@_cdecl("BatoSwiftWorkspaceCommand")
@MainActor public func workspaceCommand(_ token: UInt64, _ command: Int32, _ browserID: Int32) {
    precondition(Thread.isMainThread)
    guard let controller = workspaceSlots[token]?.controller else { return }
    if command == 3 { controller.resumeCommittedSelection() }
    if command == 1 { controller.newTab() }
    if command == 4 { controller.copyCurrentLink() }
    if command == 5 { controller.openEssential(.history) }
    if command == 6 { controller.openEssential(.downloads) }
    if command == 7 { controller.showSettings() }
    if command == 8 { controller.reopenClosedTab() }
    if (40..<60).contains(command) { controller.reopenClosedTab(at: Int(command) - 40) }
    if command == 35 { controller.showWindow() }
    if command == 31 { controller.duplicateSelection() }
    if command == 32 { controller.togglePinSelection() }
    if command == 33 { controller.closeOtherTemporaryTabs() }
    if command == 34 { controller.closeTemporaryTabsBelowSelection() }
    if command == 30 { controller.openSiteSettings() }
    if command == 9 { controller.selectAdjacentPage(step: 1) }
    if command == 10 { controller.selectAdjacentPage(step: -1) }
    if (21...29).contains(command) { controller.selectPage(shortcut: Int(command) - 20) }
    if command == 2, workspaceSlots[token]?.engine?.transient[browserID] != nil {
        controller.dismissPeek()
    } else if command == 2, let page = workspaceSlots[token]?.engine?.pages[browserID] {
        controller.receive(.selected(page))
        if controller.runtime.state.currentWorkspace.activeEntryID == page.entryID {
            controller.closeSelection()
        }
    }
}


/// Chromium builds its menu titles from its own product name ("Quit Chromium"); the app is Bato.
/// Menus for features Bato replaces (Bookmarks, Chromium Profiles, vertical tabs) are hidden or removed.
/// Titles are rewritten when the shortcuts install and again whenever a menu opens, because
/// Chromium refreshes some items as menus open.
/// Chrome enables Tab > Close Tabs to the Right from its own strip order, which is creation order and not
/// the sidebar's. The item is retargeted here so its enable state and action follow the sidebar.
@MainActor private final class CloseTabsBelowItem: NSObject, NSMenuItemValidation {
    static let title = "Close Tabs to the Right"
    static let shared = CloseTabsBelowItem()
    @objc func closeTabsBelow(_ sender: Any?) { workspaceHost.controller?.closeTemporaryTabsBelowSelection() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { workspaceHost.controller?.canCloseTemporaryTabsBelowSelection ?? false }
}

@MainActor private enum MenuBranding {
    private static var observer: NSObjectProtocol?

    static func install() {
        apply(to: NSApp.mainMenu)
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { apply(to: NSApp.mainMenu) }
        }
    }

    /// Chromium re-shows a hidden item as its menu opens, so unwanted items are removed instead.
    private static func apply(to menu: NSMenu?, topLevel: Bool = true) {
        for item in menu?.items ?? [] {
            if item.title.contains("Chromium") { item.title = item.title.replacingOccurrences(of: "Chromium", with: "Bato") }
            if topLevel, ChromiumMenuPolicy.hidesMenu(titled: item.title) {
                item.isHidden = true
            } else if !topLevel, ChromiumMenuPolicy.hidesItem(titled: item.title) {
                menu?.removeItem(item)
                continue
            }
            if !topLevel, item.title == CloseTabsBelowItem.title {
                item.target = CloseTabsBelowItem.shared
                item.action = #selector(CloseTabsBelowItem.closeTabsBelow(_:))
            }
            apply(to: item.submenu, topLevel: false)
        }
    }
}

/// Chromium titles a window "<page> - Chromium" from a resource string; the title is shortened here
/// instead of rebuilding the engine's resources.
@MainActor private enum WindowTitleBranding {
    private static var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private static var notifications: [NSObjectProtocol] = []
    private static let suffix = " - Chromium"

    static func install() {
        track(NSApp.windows)
        guard notifications.isEmpty else { return }
        let center = NotificationCenter.default
        notifications = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { if let window = note.object as? NSWindow { track([window]) } }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { if let window = note.object as? NSWindow { observations[ObjectIdentifier(window)] = nil } }
            },
        ]
    }

    static func brandedTitle(_ title: String) -> String {
        if title == "Chromium" { return "Bato" }
        return title.hasSuffix(suffix) ? String(title.dropLast(suffix.count)) : title
    }

    private static func track(_ windows: [NSWindow]) {
        for window in windows where observations[ObjectIdentifier(window)] == nil {
            rebrand(window)
            observations[ObjectIdentifier(window)] = window.observe(\.title) { window, _ in
                MainActor.assumeIsolated { rebrand(window) }
            }
        }
    }

    private static func rebrand(_ window: NSWindow) {
        let branded = brandedTitle(window.title)
        if branded != window.title { window.title = branded }
    }
}

/// Route physical T/W before Chromium's page-focused key-equivalent path.
/// Leave Chromium's menu items intact for untracked tabs and menu commands.
@MainActor private final class WorkspaceKeyRouter: NSObject {
    private var token: UInt64
    private weak var root: NSView?
    private weak var ownedWindow: NSWindow?
    private var keyMonitor: Any?
    private var acceptedKeys: Set<UInt16> = []
    private var deactivationObserver: NSObjectProtocol?
    private let toggle: () -> Bool
    private let dismissPeek: () -> Bool
    private let promotePeek: () -> Bool
    private let editAddress: () -> Bool
    private let copyLink: () -> Bool
    private let pageItems: () -> [NSMenuItem]
    private var sidebarMenuItem: NSMenuItem?
    private var peekMenuItem: NSMenuItem?
    private var pageMenuItem: NSMenuItem?
    private var spacesMenuItem: NSMenuItem?
    private var copyURLItems: [NSMenuItem] = []
    init(token: UInt64, root: NSView, toggle: @escaping () -> Bool,
         dismissPeek: @escaping () -> Bool, promotePeek: @escaping () -> Bool,
         editAddress: @escaping () -> Bool, copyLink: @escaping () -> Bool,
         pageItems: @escaping () -> [NSMenuItem]) {
        self.token = token; self.root = root; self.toggle = toggle
        self.dismissPeek = dismissPeek; self.promotePeek = promotePeek
        self.editAddress = editAddress; self.copyLink = copyLink; self.pageItems = pageItems
        super.init()
    }
    /// The sidebar moved to another window: its shortcuts now belong to that window.
    func retarget(token: UInt64, root: NSView) {
        self.token = token
        self.root = root
        ownedWindow = root.window
    }
    @objc private func toggleFromMenu() { _ = toggle() }
    @objc private func promotePeekFromMenu() { _ = promotePeek() }
    @objc private func copyLinkFromMenu() { _ = copyLink() }
    @objc private func copyMarkdownFromMenu() { _ = workspaceHost.controller?.copyCurrentLink(as: .markdown) }
    @objc private func spaceFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { workspaceHost.controller?.switchToSpace(id) }
    }
    @objc private func nextSpaceFromMenu() { workspaceHost.controller?.switchToAdjacentSpace(next: true) }
    @objc private func previousSpaceFromMenu() { workspaceHost.controller?.switchToAdjacentSpace(next: false) }
    @objc private func newSpaceFromMenu() { workspaceHost.controller?.addSpace() }

    /// Menu key equivalents reach Bato where the sidebar view's performKeyEquivalent does not
    /// while Chromium owns focus, so Control-1…9 live here. Rebuilt on every workspace change.
    private func refreshSpaces() {
        guard let menu = spacesMenuItem?.submenu, let controller = workspaceHost.controller else { return }
        menu.removeAllItems()
        for entry in controller.spaceMenuEntries {
            let item = NSMenuItem(title: entry.title, action: #selector(spaceFromMenu(_:)),
                                  keyEquivalent: entry.shortcut.map(String.init) ?? "")
            item.keyEquivalentModifierMask = entry.shortcut == nil ? [] : .control
            item.target = self
            item.representedObject = entry.id
            item.state = entry.isActive ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let next = NSMenuItem(title: "Next Space", action: #selector(nextSpaceFromMenu),
                              keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        let previous = NSMenuItem(title: "Previous Space", action: #selector(previousSpaceFromMenu),
                                  keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        for item in [next, previous] { item.keyEquivalentModifierMask = [.command, .control] }
        let create = NSMenuItem(title: "New Space", action: #selector(newSpaceFromMenu), keyEquivalent: "")
        for item in [next, previous, create] { item.target = self; menu.addItem(item) }
    }

    /// Edit > Copy URL carries Shift-Cmd-C: Chromium's Inspect chord is claimed before it reaches the Developer menu.
    private func installCopyURLItems(in mainMenu: NSMenu) {
        guard copyURLItems.isEmpty,
              let edit = mainMenu.items.first(where: { $0.title == "Edit" })?.submenu else { return }
        let copy = NSMenuItem(title: "Copy URL", action: #selector(copyLinkFromMenu), keyEquivalent: "c")
        copy.keyEquivalentModifierMask = [.command, .shift]
        let markdown = NSMenuItem(title: "Copy URL as Markdown", action: #selector(copyMarkdownFromMenu), keyEquivalent: "c")
        markdown.keyEquivalentModifierMask = [.command, .shift, .option]
        copyURLItems = [copy, markdown]
        copyURLItems.forEach { $0.target = self }
        let after = edit.items.firstIndex { $0.title == "Copy" }.map { $0 + 1 } ?? edit.items.count
        copyURLItems.enumerated().forEach { edit.insertItem($1, at: after + $0) }
    }
    func install() {
        if let window = root?.window { ownedWindow = window }
        if sidebarMenuItem == nil, let mainMenu = NSApp.mainMenu {
            let item = NSMenuItem(title: "Sidebar", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Sidebar")
            let toggleItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleFromMenu), keyEquivalent: "s")
            toggleItem.target = self
            toggleItem.keyEquivalentModifierMask = .command
            menu.addItem(toggleItem)
            item.submenu = menu
            mainMenu.addItem(item)
            sidebarMenuItem = item
        }
        if peekMenuItem == nil, let mainMenu = NSApp.mainMenu {
            let item = NSMenuItem(title: "Peek", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Peek")
            let promoteItem = NSMenuItem(title: "Open as Tab", action: #selector(promotePeekFromMenu), keyEquivalent: "\r")
            promoteItem.target = self
            promoteItem.keyEquivalentModifierMask = [.command, .option]
            menu.addItem(promoteItem)
            item.submenu = menu
            mainMenu.addItem(item)
            peekMenuItem = item
        }
        if pageMenuItem == nil, let mainMenu = NSApp.mainMenu {
            let item = NSMenuItem(title: "Page", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Page")
            pageItems().forEach(menu.addItem)
            item.submenu = menu
            mainMenu.addItem(item)
            pageMenuItem = item
        }
        if let mainMenu = NSApp.mainMenu {
            installCopyURLItems(in: mainMenu)
            if spacesMenuItem == nil {
                let item = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
                item.submenu = NSMenu(title: "Spaces")
                let window = mainMenu.items.firstIndex { $0.title == "Window" } ?? mainMenu.items.count
                mainMenu.insertItem(item, at: window)
                spacesMenuItem = item
                workspaceHost.controller?.onSpacesChanged = { [weak self] in self?.refreshSpaces() }
                refreshSpaces()
            }
        }
        MenuBranding.install()
        WindowTitleBranding.install()
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                // AppKit delivers local event monitors on the main thread.
                MainActor.assumeIsolated {
                    guard let self else { return event }
                    return self.routeKey(event)
                }
            }
        }
        if deactivationObserver == nil {
            deactivationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.acceptedKeys.removeAll() }
            }
        }
    }
    func restore() {
        if let sidebarMenuItem { sidebarMenuItem.menu?.removeItem(sidebarMenuItem) }
        sidebarMenuItem = nil
        if let peekMenuItem { peekMenuItem.menu?.removeItem(peekMenuItem) }
        peekMenuItem = nil
        if let pageMenuItem { pageMenuItem.menu?.removeItem(pageMenuItem) }
        pageMenuItem = nil
        if let spacesMenuItem { spacesMenuItem.menu?.removeItem(spacesMenuItem) }
        spacesMenuItem = nil
        workspaceHost.controller?.onSpacesChanged = nil
        copyURLItems.forEach { $0.menu?.removeItem($0) }
        copyURLItems = []
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
        acceptedKeys.removeAll()
        ownedWindow = nil
    }
    private func logKeyRouting(_ key: String, handled: Bool) {
        FileHandle.standardError.write(Data("{\"event\":\"workspace-key-routed\",\"key\":\"\(key)\",\"handled\":\(handled)}\n".utf8))
    }
    private func routeKey(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyUp {
            acceptedKeys.remove(event.keyCode)
            return event
        }
        if event.type == .flagsChanged {
            if !event.modifierFlags.contains(.command) { acceptedKeys.removeAll() }
            return event
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        // Escape is consumed only while a dismissable Peek is presented, so a
        // pending before-unload prompt still receives it.
        if event.keyCode == 53, modifiers.isEmpty, NSApp.isActive, let window = ownedWindow,
           event.window === window, NSApp.keyWindow === window,
           window.attachedSheet == nil, NSApp.modalWindow == nil, dismissPeek() { return nil }
        if event.keyCode == 36, modifiers == [.command, .option], NSApp.isActive, let window = ownedWindow,
           event.window === window, NSApp.keyWindow === window,
           window.attachedSheet == nil, NSApp.modalWindow == nil, promotePeek() { return nil }
        // Cmd-L and Cmd-Shift-C are claimed only for a live Bato page, ahead of Chromium's accelerators
        // (Cmd-Shift-C is its Inspect Element, still on Cmd-Option-C and the context menu). An untracked Chrome tab,
        // the blank anchor, a presented Peek or a sheet leave the key to Chromium (Cmd-L keeps
        // focusing its omnibox, which remains visible and authoritative for origin/security UI).
        if (modifiers == .command || modifiers == [.command, .shift]),
           let key = event.charactersIgnoringModifiers?.lowercased(),
           (modifiers == .command && key == "l") || (modifiers != .command && key == "c"),
           NSApp.isActive, let window = ownedWindow, event.window === window, NSApp.keyWindow === window,
           window.attachedSheet == nil, NSApp.modalWindow == nil {
            if event.isARepeat { return acceptedKeys.contains(event.keyCode) ? nil : event }
            acceptedKeys.remove(event.keyCode)
            let handled = key == "l" ? editAddress() : copyLink()
            if key == "c" { logKeyRouting("copy-url", handled: handled) }
            guard handled else { return event }
            acceptedKeys.insert(event.keyCode)
            return nil
        }
        guard modifiers == .command,
              let key = event.charactersIgnoringModifiers, key == "t" || key == "w" || key == "s",
              NSApp.isActive, let window = ownedWindow,
              event.window === window, NSApp.keyWindow === window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return event }
        // T/W retain their existing requirement for an attached native slot.
        if key != "s", root?.window !== window { return event }
        // Keep suppressing an accepted physical sequence if its first close
        // exposes an untracked Chrome tab. Repeats begun there still pass through.
        if event.isARepeat { return acceptedKeys.contains(event.keyCode) ? nil : event }
        acceptedKeys.remove(event.keyCode) // A new physical sequence supersedes stale state.
        // The bridge also rejects blocked pages, slot transitions and closing
        // windows. Negative means an untracked Chrome tab or unavailable slot.
        if key == "s" {
            // In fullscreen the shortcut shows or hides the floating sidebar and is never forwarded to
            // Chromium's Save Page command, even when no sidebar is reachable.
            if window.styleMask.contains(.fullScreen) {
                _ = toggle()
                acceptedKeys.insert(event.keyCode)
                return nil
            }
            guard toggle() else { return event }
            acceptedKeys.insert(event.keyCode)
            return nil
        }
        let active = activePage?(token) ?? -1
        guard active >= 0 else { return event }
        acceptedKeys.insert(event.keyCode)
        if key == "t" { workspaceCommand(token, 1, active) }
        if key == "w", active > 0 { workspaceCommand(token, 2, active) }
        // CmdW on the protected blank anchor deliberately does nothing, matching
        // the protected placeholder policy; it must never close the workspace's host window.
        return nil
    }
}

// The bytes are borrowed only for this C callback. Resolve the exact live
// generation again; detached slots and closed/replaced pages cannot receive icons.
@_cdecl("BatoSwiftWorkspacePageIcon")
@MainActor public func workspacePageIcon(_ token: UInt64, _ browserID: Int32,
                                        _ png: UnsafePointer<UInt8>?, _ size: Int) {
    precondition(Thread.isMainThread)
    guard size >= 0, size <= 256 * 1024,
          let slot = workspaceSlots[token], let page = slot.engine?.pages[browserID],
          slot.controller?.runtime.livePages[page.entryID] == page else { return }
    let data = png.map { Data(bytes: $0, count: size) }
    slot.controller?.receivePageIcon(entryID: page.entryID, png: data)
}

@_cdecl("BatoSwiftWorkspaceConfigureSplits")
@MainActor public func configureWorkspaceSplits(
    _ present: @escaping @convention(c) (UInt64, Int32, Int32, Int32, Double) -> Int32,
    _ separate: @escaping @convention(c) (UInt64) -> Int32) {
    precondition(Thread.isMainThread)
    presentSplitPages = present
    separateSplitPages = separate
}

@_cdecl("BatoSwiftWorkspaceSplitChanged")
@MainActor public func workspaceSplitChanged(_ token: UInt64, _ left: Int32, _ right: Int32,
                                            _ ratio: Double, _ removed: Int32) {
    precondition(Thread.isMainThread)
    guard let slot = workspaceSlots[token], let engine = slot.engine,
          let a = engine.pages[left], let b = engine.pages[right],
          let controller = slot.controller,
          controller.runtime.livePages[a.entryID] == a,
          controller.runtime.livePages[b.entryID] == b else { return }
    if removed == 1 { controller.receive(.splitSeparated(left: a, right: b)) }
    else { controller.receive(.splitRatioChanged(left: a, right: b, ratio: ratio)) }
}

@_cdecl("BatoSwiftWorkspaceConfigurePeek")
@MainActor public func configureWorkspacePeek(
    _ present: @escaping @convention(c) (UInt64, Int32, Int32) -> UInt64,
    _ end: @escaping @convention(c) (UInt64, UInt64, Int32) -> Int32) {
    precondition(Thread.isMainThread)
    presentPeekPages = present
    endPeekPages = end
}

@_cdecl("BatoSwiftWorkspacePeekEnded")
@MainActor public func workspacePeekEnded(_ token: UInt64, _ generation: UInt64, _ parent: Int32,
                                         _ preview: Int32, _ reason: Int32) {
    precondition(Thread.isMainThread)
    guard let slot = workspaceSlots[token], let engine = slot.engine, let controller = slot.controller,
          let current = engine.peek, current.generation == generation,
          current.parent == parent, current.preview == preview,
          let page = engine.transient[preview] ?? engine.pages[preview],
          let reason = PeekEndReason(rawValue: reason) else { return }
    engine.peek = nil
    controller.receive(.peekEnded(preview: page, reason: reason))
}

@_cdecl("BatoSwiftWorkspacePeekScrimClicked")
@MainActor public func workspacePeekScrimClicked(_ token: UInt64, _ generation: UInt64,
                                                _ parent: Int32, _ preview: Int32) {
    precondition(Thread.isMainThread)
    guard let slot = workspaceSlots[token], let engine = slot.engine, let controller = slot.controller,
          let current = engine.peek, current.generation == generation,
          current.parent == parent, current.preview == preview,
          let page = engine.transient[preview] else { return }
    controller.dismissPeek(preview: page)
}

/// Runs inside the engine's navigation request: no mutation here.
@_cdecl("BatoSwiftWorkspacePeekLinkEligible")
@MainActor public func workspacePeekLinkEligible(_ token: UInt64, _ parent: Int32,
                                                _ url: UnsafePointer<CChar>) -> Int32 {
    precondition(Thread.isMainThread)
    guard let slot = workspaceSlots[token], let engine = slot.engine, let controller = slot.controller,
          engine.peek == nil, let page = engine.pages[parent],
          let address = URL(string: String(cString: url)) else { return 0 }
    return controller.runtime.canOpenPeek(from: page, url: address) ? 1 : 0
}

@_cdecl("BatoSwiftWorkspacePeekLinkRequested")
@MainActor public func workspacePeekLinkRequested(_ token: UInt64, _ parent: Int32,
                                                 _ url: UnsafePointer<CChar>) {
    precondition(Thread.isMainThread)
    let text = String(cString: url)
    guard let slot = workspaceSlots[token], let engine = slot.engine, let controller = slot.controller,
          let page = engine.pages[parent], let address = URL(string: text) else { return }
    controller.openPeek(from: page, url: address)
}

/// A link that asked for a new tab without an opener (target=_blank, Open Link in New Tab) becomes a sidebar tab.
@_cdecl("BatoSwiftWorkspaceOpenLinkInTab")
@MainActor public func workspaceOpenLinkInTab(_ token: UInt64, _ parent: Int32, _ url: UnsafePointer<CChar>) {
    precondition(Thread.isMainThread)
    guard let slot = workspaceSlots[token], let engine = slot.engine, let controller = slot.controller,
          engine.pages[parent] != nil, let address = URL(string: String(cString: url)) else { return }
    controller.openExternalURL(address)
}

@_cdecl("BatoSwiftWorkspaceConfigureNavigation")
@MainActor public func configureWorkspaceNavigation(
    _ navigate: @escaping @convention(c) (UInt64, Int32, UnsafePointer<CChar>?) -> Int32) {
    precondition(Thread.isMainThread)
    navigatePage = navigate
}


@_cdecl("BatoSwiftWorkspaceConfigureProfiles")
@MainActor public func configureWorkspaceProfiles(
    _ open: @escaping @convention(c) (UnsafePointer<CChar>?, Int32) -> Int32) {
    precondition(Thread.isMainThread)
    openProfileWindow = open
}

/// token is the bound window's slot, or 0 when the request failed or timed out.
@_cdecl("BatoSwiftWorkspaceProfileWindowReady")
@MainActor public func workspaceProfileWindowReady(_ token: UInt64, _ key: UnsafePointer<CChar>?, _ ok: Int32) {
    precondition(Thread.isMainThread)
    guard let key, let profileID = UUID(uuidString: String(cString: key)) else { return }
    workspaceHost.engine?.windowRequestFinished(profileID: profileID, token: ok == 1 ? token : nil)
}

@_cdecl("BatoSwiftWorkspaceConfigureProfileDelete")
@MainActor public func configureWorkspaceProfileDelete(
    _ destroy: @escaping @convention(c) (UnsafePointer<CChar>?) -> Int32) {
    precondition(Thread.isMainThread)
    deleteProfileData = destroy
}

@_cdecl("BatoSwiftDownloadsConfigure")
@MainActor public func configureDownloads(
    _ snapshot: @escaping @convention(c) () -> Int32,
    _ act: @escaping @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32) -> Int32) {
    precondition(Thread.isMainThread)
    downloadSnapshot = snapshot
    downloadAct = act
}

@_cdecl("BatoSwiftDownloadUpserted")
@MainActor public func downloadUpserted(_ profileKey: UnsafePointer<CChar>, _ id: UnsafePointer<CChar>,
                                        _ filename: UnsafePointer<CChar>, _ path: UnsafePointer<CChar>,
                                        _ received: Int64, _ total: Int64, _ bytesPerSecond: Int64,
                                        _ state: Int32, _ canResume: Int32, _ fileExists: Int32, _ warning: Int32) {
    precondition(Thread.isMainThread)
    nativeDownloads?.onEvent?(.upsert(DownloadItem(
        engineProfileKey: String(cString: profileKey), id: String(cString: id),
        filename: String(cString: filename), path: String(cString: path), receivedBytes: received,
        totalBytes: total, bytesPerSecond: bytesPerSecond, state: state, canResume: canResume != 0,
        fileExists: fileExists != 0, warning: warning)))
}

@_cdecl("BatoSwiftDownloadRemoved")
@MainActor public func downloadRemoved(_ profileKey: UnsafePointer<CChar>, _ id: UnsafePointer<CChar>) {
    precondition(Thread.isMainThread)
    nativeDownloads?.onEvent?(.removed(profileKey: String(cString: profileKey), id: String(cString: id)))
}

@_cdecl("BatoSwiftAudioConfigure")
@MainActor public func configureAudio(_ setMuted: @escaping @convention(c) (Int32, Int32) -> Int32) {
    precondition(Thread.isMainThread)
    setPageMuted = setMuted
    TabAudioCenter.shared.setMuted = { entryID, muted in
        guard let engine = workspaceHost.engine,
              let id = engine.pages.first(where: { $0.value.entryID == entryID })?.key else { return false }
        return setPageMuted?(id, muted ? 1 : 0) == 1
    }
}

/// Only organization pages carry audio badges; a preview or a closed page is ignored.
@_cdecl("BatoSwiftAudioChanged")
@MainActor public func audioChanged(_ browserID: Int32, _ audible: Int32, _ muted: Int32) {
    precondition(Thread.isMainThread)
    guard let page = workspaceHost.engine?.pages[browserID] else { return }
    TabAudioCenter.shared.update(entryID: page.entryID, audible: audible != 0, muted: muted != 0)
}
