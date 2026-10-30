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
    var menuRouter: WorkspaceMenuRouter?
    init(token: UInt64, directory: URL) {
        do {
            let controller = try NativeWorkspaceController(directory: directory) { profileID in
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
            let router = WorkspaceMenuRouter(token: token, root: root)
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


/// Cocoa menu key equivalents can bypass CEF's per-browser command hook.
/// Override only standard T/W items while this one workspace owns the key window.
@MainActor private final class WorkspaceMenuRouter: NSObject, NSMenuItemValidation {
    private let token: UInt64
    private weak var root: NSView?
    private var originals: [(NSMenuItem, AnyObject?, Selector?, Int32)] = []
    init(token: UInt64, root: NSView) { self.token = token; self.root = root }
    func install() {
        guard originals.isEmpty, let menu = NSApp.mainMenu else { return }
        let newTag = commandID?(1) ?? -1
        let closeTag = commandID?(2) ?? -1
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { visit(submenu) }
                let modifiers = item.keyEquivalentModifierMask.intersection([.command, .shift, .control, .option])
                let command: Int32
                if newTag > 0 && item.tag == newTag { command = 1 }
                else if closeTag > 0 && item.tag == closeTag { command = 2 }
                else if modifiers == .command && item.keyEquivalent == "t" { command = 1 }
                else if modifiers == .command && item.keyEquivalent == "w" { command = 2 }
                else { continue }
                originals.append((item, item.target as AnyObject?, item.action, command))
                item.target = self
                item.action = #selector(dispatch(_:))
            }
        }
        visit(menu)
    }
    func restore() {
        for (item, target, action, _) in originals where (item.target as AnyObject?) === self {
            item.target = target
            item.action = action
        }
        originals.removeAll()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
    @objc private func dispatch(_ item: NSMenuItem) {
        // Menu tracking can temporarily change the key window and restore its
        // responder after the action. Resolve/focus after that stack unwinds.
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self, let item else { return }
            self.perform(item)
        }
    }
    private func perform(_ item: NSMenuItem) {
        guard let original = originals.first(where: { $0.0 === item }) else { return }
        let active = activePage?(token) ?? -1
        guard let window = root?.window,
              (NSApp.keyWindow === window || NSApp.mainWindow === window), active >= 0 else {
            if let action = original.2 { NSApp.sendAction(action, to: original.1, from: item) }
            return
        }
        if original.3 == 1 { workspaceCommand(token, 1, active) }
        if original.3 == 2, active > 0 { workspaceCommand(token, 2, active) }
    }
}
