import AppKit

// Diagnostic injection only. This does not reparent CEF's compositor views or
// claim to make a Chrome-style browser embeddable in a Swift-owned NSWindow.
private func report(_ event: String, _ values: [String: Any] = [:]) {
    var record = values
    record["event"] = event
    record["probe"] = "bato-native-composition"
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data([10]))
    }
}

private final class Accessory: NSTitlebarAccessoryViewController {
    private let status = NSTextField(labelWithString: "Bato Swift/AppKit probe")
    private let input = NSTextField(string: "Native focus target")
    private var count = 0

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 38))
        root.translatesAutoresizingMaskIntoConstraints = false
        root.heightAnchor.constraint(equalToConstant: 38).isActive = true
        root.widthAnchor.constraint(greaterThanOrEqualToConstant: 580).isActive = true
        status.frame = NSRect(x: 12, y: 10, width: 210, height: 20)
        input.frame = NSRect(x: 230, y: 6, width: 190, height: 24)
        let button = NSButton(title: "Native action", target: self, action: #selector(clicked))
        button.frame = NSRect(x: 430, y: 5, width: 140, height: 26)
        root.addSubview(status)
        root.addSubview(input)
        root.addSubview(button)
        view = root
    }

    @objc private func clicked() {
        count += 1
        status.stringValue = "Native action count: \(count)"
        report("native-action", ["count": count, "inWindow": view.window != nil])
    }

    func exercise(in window: NSWindow) {
        clicked()
        let oldResponder = window.firstResponder
        let accepted = window.makeFirstResponder(input)
        report("native-focus", ["accepted": accepted, "firstResponderClass": window.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "none"])
        if let oldResponder { _ = window.makeFirstResponder(oldResponder) }
        let oldFrame = window.frame
        var larger = oldFrame
        larger.size.width += 32
        window.setFrame(larger, display: true)
        report("resize", ["widthBefore": oldFrame.width, "widthAfter": window.frame.width])
        window.setFrame(oldFrame, display: true)
    }
}

private final class NativeProbe {
    static let shared = NativeProbe()
    private var observers: [NSObjectProtocol] = []
    private var attached: [ObjectIdentifier: Accessory] = [:]

    func install() {
        report("installed", ["pid": ProcessInfo.processInfo.processIdentifier, "mainThread": Thread.isMainThread])
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            if let window = notification.object as? NSWindow { self?.attach(to: window) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.attached.removeValue(forKey: ObjectIdentifier(window))
            report("window-close", ["windowClass": NSStringFromClass(type(of: window))])
        })
        for window in NSApplication.shared.windows where window.isVisible { attach(to: window) }
    }

    private func attach(to window: NSWindow) {
        guard !(window is NSPanel), window.styleMask.contains(.titled),
              window.frame.width >= 600, window.frame.height >= 300 else { return }
        let key = ObjectIdentifier(window)
        guard attached[key] == nil else { return }
        let accessory = Accessory()
        accessory.layoutAttribute = .bottom
        attached[key] = accessory
        window.addTitlebarAccessoryViewController(accessory)
        report("accessory-attached", ["windowClass": NSStringFromClass(type(of: window)), "contentClass": window.contentView.map { NSStringFromClass(type(of: $0)) } ?? "none", "accessoryCount": window.titlebarAccessoryViewControllers.count, "contentWidth": window.contentView?.bounds.width ?? 0, "contentHeight": window.contentView?.bounds.height ?? 0])
        if let content = window.contentView { describe(content, depth: 0) }
        if ProcessInfo.processInfo.environment["BATO_NATIVE_PROBE_AUTOTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak accessory, weak window] in
                guard let accessory, let window else { return }
                accessory.exercise(in: window)
                report("accessory-state", ["viewInWindow": accessory.view.window === window, "hidden": accessory.view.isHidden, "visibleRectWidth": accessory.view.visibleRect.width, "visibleRectHeight": accessory.view.visibleRect.height, "frameWidth": accessory.view.frame.width, "frameHeight": accessory.view.frame.height])
            }
        }
    }

    private func describe(_ view: NSView, depth: Int) {
        guard depth <= 5 else { return }
        report("view", ["depth": depth, "class": NSStringFromClass(type(of: view)), "width": view.bounds.width, "height": view.bounds.height])
        for child in view.subviews.prefix(16) { describe(child, depth: depth + 1) }
    }
}

@_cdecl("BatoInstallNativeProbe")
public func installNativeProbe() {
    NativeProbe.shared.install()
}
