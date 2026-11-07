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
@MainActor private var workspaceSlots: [UInt64: WorkspaceSlot] = [:]

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
            onEvent?(.closed(page))
        case 3: onEvent?(.closeCancelled(page))
        case 4:
            pages.removeValue(forKey: id)
            transient.removeValue(forKey: id)
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
        content?.frame = NSRect(x: 0, y: 0, width: max(214, bounds.width - 6), height: bounds.height)
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
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: max(4, (bounds.height - 30) / 2), width: 2, height: 30),
                     xRadius: 1, yRadius: 1).fill()
    }
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
    private var width: Int32 = 260
    private var mode: Int32 = 1
    private var pointerMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var keyObserver: NSObjectProtocol?
    private var menuTracking = false
    private var changingGeometry = false
    let token: UInt64
    /// The first slot owns organization; later slots are windows of other Profiles that borrow its sidebar.
    init(token: UInt64, directory: URL?) {
        self.token = token
        root.onEnter = { [weak self] in self?.reveal() }
        root.onExit = { [weak self] in self?.dismissPeek() }
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
            let message = NSTextField(wrappingLabelWithString:
                "Organization unavailable. Its existing file has been left intact. Close Bato and check the file before reopening.")
            message.frame = NSRect(x: 14, y: 24, width: 232, height: 130)
            root.addSubview(message)
        }
    }
    private func attached() {
        installPointerMonitor()
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
        if mode == 0, !setGeometry(mode: 2) { return }
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
    @discardableResult private func setGeometry(width requested: Int32? = nil, mode next: Int32) -> Bool {
        guard canInteract, !changingGeometry else { return false }
        changingGeometry = true
        defer { changingGeometry = false }
        guard sidebarGeometry?(token, requested ?? width, next) == 1 else { return false }
        width = requested ?? width
        mode = next
        root.mode = next
        root.layoutSubtreeIfNeeded()
        return true
    }
    @discardableResult func toggle() -> Bool {
        guard setGeometry(mode: mode == 1 ? 0 : 1) else { return false }
        if mode == 0 { _ = pageFocus?(token) }
        return true
    }
    private func reveal() {
        guard mode == 0, canInteract, !menuTracking else { return }
        _ = setGeometry(mode: 2) // Hover never steals focus from the page.
    }
    private func dismissPeek(force: Bool = false) {
        guard mode == 2, canInteract, !menuTracking else { return }
        if !force, let focused = root.window?.firstResponder as? NSView,
           focused === root || focused.isDescendant(of: root) { return }
        if setGeometry(mode: 0), force { _ = pageFocus?(token) }
    }
    private func installPointerMonitor() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.root.window,
                   !self.root.bounds.contains(self.root.convert(event.locationInWindow, from: nil)) {
                    self.dismissPeek(force: true)
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
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll()
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
    if command == 2, workspaceSlots[token]?.engine?.transient[browserID] != nil {
        controller.dismissPeek()
    } else if command == 2, let page = workspaceSlots[token]?.engine?.pages[browserID] {
        controller.receive(.selected(page))
        if controller.runtime.state.currentWorkspace.activeEntryID == page.entryID {
            controller.closeSelection()
        }
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
            let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyLinkFromMenu), keyEquivalent: "c")
            copyItem.target = self
            copyItem.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(copyItem)
            let extra = pageItems()
            if !extra.isEmpty { menu.addItem(.separator()) }
            extra.forEach(menu.addItem)
            item.submenu = menu
            mainMenu.addItem(item)
            pageMenuItem = item
        }
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
            // Fullscreen detaches the native slot. Retain the owned window's
            // shortcut without forwarding it to Chromium's Save Page command.
            if window.styleMask.contains(.fullScreen) {
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
