import AppKit

// Explicitly linked experiment. The companion panel occupies its own screen
// rectangle. It does not reserve space inside Chrome or reparent Chromium views.
private typealias Callback = @convention(c) (Int32, Int32) -> Void
private func report(_ event: String, _ extra: [String: Any] = [:]) {
    var value = extra
    value["event"] = event
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        FileHandle.standardError.write(data + Data([10]))
    }
}

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class Companion: NSObject {
    weak var browserWindow: NSWindow?
    let panel: NSPanel
    var identifiers: Set<Int32> = []
    var callback: Callback
    var activeIdentifier: Int32
    private var observers: [NSObjectProtocol] = []
    private let status = NSTextField(labelWithString: "Linked Swift bridge")
    private let input = NSTextField(string: "Native focus target")
    private var count = 0

    init(window: NSWindow, identifier: Int32, callback: @escaping Callback) {
        browserWindow = window
        activeIdentifier = identifier
        self.callback = callback
        panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 224, height: 340), styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = "Bato bridge experiment"
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = false
        panel.isReleasedWhenClosed = false
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 14, bottom: 14, right: 14)
        root.addArrangedSubview(status)
        root.addArrangedSubview(input)
        for (title, selector) in [("Native action", #selector(clicked)), ("Focus browser", #selector(focusBrowser)), ("New native split", #selector(split)), ("Close all browsers", #selector(closeBrowsers)), ("Quit application", #selector(quitApplication))] {
            root.addArrangedSubview(NSButton(title: title, target: self, action: selector))
        }
        panel.contentView = root
        if let screen = window.screen ?? NSScreen.main {
            var frame = window.frame
            let available = screen.visibleFrame
            let left = max(available.minX, frame.minX)
            frame.origin.x = left + 240
            frame.size.width = min(frame.width, available.maxX - frame.minX)
            if frame.width >= 640 { window.setFrame(frame, display: true) }
        }
        placePanel()
        window.addChildWindow(panel, ordered: .above)
        NSApp.addWindowsItem(panel, title: "Bato bridge experiment", filename: false)
        if ProcessInfo.processInfo.arguments.contains("--bato-focus-native-controls") {
            // Wait until Chrome has finished its own initial Show/activation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak panel] in
                guard let panel else { return }
                panel.makeKeyAndOrderFront(nil)
                report("linked-panel-focus-requested", ["isKeyWindow": panel.isKeyWindow])
            }
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.placePanel() })
        }
        report("linked-attached", ["mainThread": Thread.isMainThread, "windowClass": NSStringFromClass(type(of: window)), "companionOnly": true])
    }

    private func placePanel() {
        guard let window = browserWindow else { return }
        let frame = window.frame
        var panelFrame = panel.frame
        panelFrame.origin = NSPoint(x: frame.minX - panelFrame.width - 8, y: frame.maxY - panelFrame.height)
        panel.setFrame(panelFrame, display: true)
        report("companion-geometry", ["overlapsBrowser": panelFrame.intersects(frame), "browserWidth": frame.width, "panelWidth": panelFrame.width])
    }
    @objc private func clicked() {
        count += 1
        status.stringValue = "Native action count: \(count)"
        report("linked-native-action", ["count": count])
    }
    @objc private func focusBrowser() {
        guard let window = browserWindow else { return }
        window.makeKeyAndOrderFront(nil)
        callback(activeIdentifier, 1)
        report("browser-window-focus-requested", ["isKeyWindow": window.isKeyWindow])
    }
    @objc private func split() { callback(activeIdentifier, 3) }
    @objc private func closeBrowsers() { callback(activeIdentifier, 2) }
    @objc private func quitApplication() { callback(activeIdentifier, 4) }
    func detach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        browserWindow?.removeChildWindow(panel)
        NSApp.removeWindowsItem(panel)
        panel.close()
        // Do not change the closing Chrome window's geometry during teardown.
        report("linked-detached")
    }
}

private var companions: [ObjectIdentifier: Companion] = [:]
private final class ReservedSurface: NSObject {
    weak var window: NSWindow?
    let sidebar = NSView()
    let commandbar = NSView()
    var identifiers: Set<Int32> = []
    var activeIdentifier: Int32
    let callback: Callback
    private var observers: [NSObjectProtocol] = []
    private let label = NSTextField(labelWithString: "Linked Swift sidebar")
    private let stack = NSStackView()
    private var count = 0

    init(window: NSWindow, identifier: Int32, callback: @escaping Callback) {
        self.window = window
        activeIdentifier = identifier
        self.callback = callback
        super.init()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        commandbar.wantsLayer = true
        commandbar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.frame = NSRect(x: 14, y: 14, width: 232, height: 250)
        stack.addArrangedSubview(label)
        for (title, selector) in [("Native action", #selector(clicked)), ("Focus browser", #selector(focusBrowser)), ("New native split", #selector(split)), ("Close all browsers", #selector(closeBrowsers)), ("Quit application", #selector(quitApplication))] {
            stack.addArrangedSubview(NSButton(title: title, target: self, action: selector))
        }
        sidebar.addSubview(stack)
        let input = NSTextField(string: "Native command bar focus target")
        input.frame = NSRect(x: 12, y: 10, width: 310, height: 24)
        commandbar.addSubview(input)
        if let content = window.contentView {
            content.addSubview(sidebar, positioned: .above, relativeTo: nil)
            content.addSubview(commandbar, positioned: .above, relativeTo: nil)
        }
        place()
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.place() })
        }
        report("reserved-native-attached", ["mainThread": Thread.isMainThread])
    }
    private func place() {
        guard let window, let content = window.contentView else { return }
        // The exported contentView owns these sibling coordinates. CEF's
        // custom frame does not guarantee NSWindow.contentLayoutRect shares
        // that coordinate system; converting it yielded offscreen negatives.
        let bounds = content.bounds
        let top = content.isFlipped ? bounds.minY : bounds.maxY - 44
        sidebar.frame = NSRect(x: bounds.minX, y: content.isFlipped ? bounds.minY + 44 : bounds.minY, width: 260, height: max(0, bounds.height - 44))
        stack.frame = NSRect(x: 14, y: max(14, sidebar.bounds.height - 264), width: 232, height: 250)
        commandbar.frame = NSRect(x: bounds.minX, y: top, width: bounds.width, height: 44)
        report("reserved-native-geometry", ["contentWidth": bounds.width, "contentHeight": bounds.height, "sidebarWidth": sidebar.frame.width, "sidebarHeight": sidebar.frame.height, "commandbarHeight": commandbar.frame.height, "contentFlipped": content.isFlipped, "sidebarX": sidebar.frame.minX, "sidebarY": sidebar.frame.minY, "commandbarY": commandbar.frame.minY])
    }
    @objc private func clicked() { count += 1; label.stringValue = "Native action count: \(count)"; report("reserved-native-action", ["count": count]) }
    @objc private func focusBrowser() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        callback(activeIdentifier, 1)
        report("browser-window-focus-requested", ["isKeyWindow": window.isKeyWindow])
    }
    @objc private func split() { callback(activeIdentifier, 3) }
    @objc private func closeBrowsers() { callback(activeIdentifier, 2) }
    @objc private func quitApplication() { callback(activeIdentifier, 4) }
    func detach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        sidebar.removeFromSuperview()
        commandbar.removeFromSuperview()
        report("reserved-native-detached")
    }
}
private var reservedSurfaces: [ObjectIdentifier: ReservedSurface] = [:]
private var browserKeys: [Int32: ObjectIdentifier] = [:]

@_cdecl("BatoSwiftAttach")
public func attach(_ opaqueWindow: UnsafeMutableRawPointer, _ identifier: Int32, _ callback: @escaping @convention(c) (Int32, Int32) -> Void, _ reserved: Int32) {
    precondition(Thread.isMainThread)
    let window = Unmanaged<NSWindow>.fromOpaque(opaqueWindow).takeUnretainedValue()
    let key = ObjectIdentifier(window)
    if reserved != 0 {
        let surface = reservedSurfaces[key] ?? ReservedSurface(window: window, identifier: identifier, callback: callback)
        surface.identifiers.insert(identifier)
        surface.activeIdentifier = identifier
        reservedSurfaces[key] = surface
        browserKeys[identifier] = key
        report("browser-attached", ["browserID": identifier, "windowBrowserCount": surface.identifiers.count])
        return
    }
    let companion = companions[key] ?? Companion(window: window, identifier: identifier, callback: callback)
    companion.identifiers.insert(identifier)
    companion.activeIdentifier = identifier
    companions[key] = companion
    browserKeys[identifier] = key
    report("browser-attached", ["browserID": identifier, "windowBrowserCount": companion.identifiers.count])
}

@_cdecl("BatoSwiftDetach")
public func detach(_ identifier: Int32) {
    precondition(Thread.isMainThread)
    guard let key = browserKeys.removeValue(forKey: identifier) else { return }
    if let surface = reservedSurfaces[key] {
        surface.identifiers.remove(identifier)
        if surface.identifiers.isEmpty { surface.detach(); reservedSurfaces.removeValue(forKey: key) }
        else if surface.activeIdentifier == identifier, let remaining = surface.identifiers.first { surface.activeIdentifier = remaining }
        report("browser-detached", ["browserID": identifier, "remainingWindows": reservedSurfaces.count])
        return
    }
    guard let companion = companions[key] else { return }
    companion.identifiers.remove(identifier)
    if companion.identifiers.isEmpty {
        companion.detach()
        companions.removeValue(forKey: key)
    } else if companion.activeIdentifier == identifier, let remaining = companion.identifiers.first {
        companion.activeIdentifier = remaining
    }
    report("browser-detached", ["browserID": identifier, "remainingWindows": companions.count])
}

@_cdecl("BatoSwiftFocus")
public func focus(_ identifier: Int32) {
    precondition(Thread.isMainThread)
    guard let key = browserKeys[identifier] else { return }
    companions[key]?.activeIdentifier = identifier
    reservedSurfaces[key]?.activeIdentifier = identifier
    report("browser-focused", ["browserID": identifier])
}
