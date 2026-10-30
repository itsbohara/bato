import AppKit
import BatoCore
import BatoRuntime
import BatoBrowserUI

private typealias CreatePage = @convention(c) (UInt64, UnsafePointer<CChar>?) -> Int32
private typealias CommandID = @convention(c) (Int32) -> Int32
private typealias ActivePage = @convention(c) (UInt64) -> Int32
private typealias PageAction = @convention(c) (UInt64, Int32) -> Int32
@MainActor private var workspaceDirectory: URL?
@MainActor private var createPage: CreatePage?
@MainActor private var selectPage: PageAction?
@MainActor private var closePage: PageAction?
@MainActor private var activePage: ActivePage?
@MainActor private var nativeFocus: ActivePage?
@MainActor private var commandID: CommandID?
@MainActor private var workspaceSlots: [UInt64: WorkspaceSlot] = [:]

@MainActor private final class WorkspaceEngine: PageEngine {
    let supportedProfileIDs: Set<UUID>
    let token: UInt64
    var pages: [Int32: LivePage] = [:]
    var onEvent: ((PageEvent) -> Void)?
    var onAnchorLost: (() -> Void)?
    init(token: UInt64, profileID: UUID) {
        self.token = token
        supportedProfileIDs = [profileID]
    }
    func create(_ page: LivePage, url: URL) -> Bool {
        guard supportedProfileIDs.contains(page.profileID) else { return false }
        let id = url.absoluteString.withCString { createPage?(token, $0) ?? 0 }
        guard id > 0, pages[id] == nil else { return false }
        pages[id] = page
        return true
    }
    func select(_ page: LivePage?) {
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
    func requestClose(_ page: LivePage) {
        guard let id = pages.first(where: { $0.value == page })?.key else { return }
        if closePage?(token, id) != 1 { onEvent?(.closeCancelled(page)) }
    }
    func receive(id: Int32, kind: Int32, url: String, title: String) {
        if kind == 5 || kind == 7 { onAnchorLost?(); return }
        if kind == 6 && id == 0 { onEvent?(.selectionCleared); return }
        guard let page = pages[id] else { return }
        switch kind {
        case 6: onEvent?(.selected(page))
        case 1:
            guard let address = URL(string: url) else { return }
            onEvent?(.navigation(page, url: address, title: title))
        case 2:
            pages.removeValue(forKey: id)
            onEvent?(.closed(page))
        case 3: onEvent?(.closeCancelled(page))
        case 4:
            pages.removeValue(forKey: id)
            onEvent?(.unloaded(page))
        default: break
        }
    }
}

@MainActor private final class AttachedWorkspaceRoot: NSView {
    var onAttach: (() -> Void)?
    override var isFlipped: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // CEF completes tab/window attachment after the slot factory returns.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.onAttach?()
        }
    }
}

@MainActor private final class WorkspaceSlot {
    let root = AttachedWorkspaceRoot(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
    var controller: NativeWorkspaceController?
    var engine: WorkspaceEngine?
    var menuRouter: WorkspaceKeyRouter?
    init(token: UInt64, directory: URL) {
        do {
            let controller = try NativeWorkspaceController(directory: directory, handlesKeyEquivalents: false) { profileID in
                let engine = WorkspaceEngine(token: token, profileID: profileID)
                self.engine = engine
                return engine
            }
            self.controller = controller
            controller.requestNativeFocus = { _ = nativeFocus?(token) }
            engine?.onEvent = { [weak controller] event in controller?.receive(event) }
            engine?.onAnchorLost = { [weak controller] in _ = controller?.runtime.start() }
            controller.root.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(controller.root)
            NSLayoutConstraint.activate([
                controller.root.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                controller.root.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                controller.root.topAnchor.constraint(equalTo: root.topAnchor),
                controller.root.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
            let router = WorkspaceKeyRouter(token: token, root: root)
            menuRouter = router
            root.onAttach = { [weak controller, weak router] in
                controller?.start()
                router?.install()
            }
        } catch {
            let message = NSTextField(wrappingLabelWithString:
                "Organization unavailable. Its existing file has been left intact. Close Bato and check the file before reopening.")
            message.frame = NSRect(x: 14, y: 24, width: 232, height: 130)
            root.addSubview(message)
        }
    }
}

@_cdecl("BatoSwiftWorkspaceConfigure")
@MainActor public func configureWorkspace(_ directory: UnsafePointer<CChar>?,
    _ create: @escaping @convention(c) (UInt64, UnsafePointer<CChar>?) -> Int32,
    _ select: @escaping @convention(c) (UInt64, Int32) -> Int32,
    _ close: @escaping @convention(c) (UInt64, Int32) -> Int32,
    _ active: @escaping @convention(c) (UInt64) -> Int32,
    _ focus: @escaping @convention(c) (UInt64) -> Int32,
    _ command: @escaping @convention(c) (Int32) -> Int32) {
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
}

@MainActor func workspaceModeEnabled() -> Bool { workspaceDirectory != nil }

@MainActor func createWorkspaceSlot(_ token: UInt64) -> UnsafeMutableRawPointer? {
    guard let directory = workspaceDirectory, workspaceSlots.isEmpty else { return nil }
    let slot = WorkspaceSlot(token: token, directory: directory)
    workspaceSlots[token] = slot
    return Unmanaged.passUnretained(slot.root).toOpaque()
}
@MainActor func focusWorkspaceSlot(_ token: UInt64) -> UnsafeMutableRawPointer? {
    guard let slot = workspaceSlots[token] else { return nil }
    return Unmanaged.passUnretained(slot.controller?.focusTarget ?? slot.root).toOpaque()
}
@MainActor func detachWorkspaceSlot(_ token: UInt64) {
    workspaceSlots[token]?.menuRouter?.restore()
    workspaceSlots.removeValue(forKey: token)
}

@_cdecl("BatoSwiftWorkspacePageEvent")
@MainActor public func workspacePageEvent(_ token: UInt64, _ browserID: Int32, _ kind: Int32,
                                        _ url: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?) {
    precondition(Thread.isMainThread)
    workspaceSlots[token]?.engine?.receive(id: browserID, kind: kind,
        url: url.map { String(cString: $0) } ?? "", title: title.map { String(cString: $0) } ?? "")
}

@_cdecl("BatoSwiftWorkspaceCommand")
@MainActor public func workspaceCommand(_ token: UInt64, _ command: Int32, _ browserID: Int32) {
    precondition(Thread.isMainThread)
    guard let controller = workspaceSlots[token]?.controller else { return }
    if command == 1 { controller.newTab() }
    if command == 2, let page = workspaceSlots[token]?.engine?.pages[browserID] {
        controller.receive(.selected(page))
        if controller.runtime.state.currentWorkspace.activeEntryID == page.entryID {
            controller.closeSelection()
        }
    }
}


/// Route physical T/W before Chromium's page-focused key-equivalent path.
/// Leave Chromium's menu items intact for untracked tabs and menu commands.
@MainActor private final class WorkspaceKeyRouter {
    private let token: UInt64
    private weak var root: NSView?
    private var keyMonitor: Any?
    private var acceptedKeys: Set<UInt16> = []
    private var deactivationObserver: NSObjectProtocol?
    init(token: UInt64, root: NSView) { self.token = token; self.root = root }
    func install() {
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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
        acceptedKeys.removeAll()
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
        guard modifiers == .command,
              let key = event.charactersIgnoringModifiers, key == "t" || key == "w",
              NSApp.isActive, let window = root?.window,
              event.window === window, NSApp.keyWindow === window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return event }
        // Keep suppressing an accepted physical sequence if its first close
        // exposes an untracked Chrome tab. Repeats begun there still pass through.
        if event.isARepeat { return acceptedKeys.contains(event.keyCode) ? nil : event }
        acceptedKeys.remove(event.keyCode) // A new physical sequence supersedes stale state.
        // The bridge also rejects blocked pages, slot transitions and closing
        // windows. Negative means an untracked Chrome tab or unavailable slot.
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
