import AppKit

private typealias FocusBrowser = @convention(c) (UInt64) -> Int32
private typealias AdvanceFocus = @convention(c) (UInt64, Int32) -> Int32
private var focusBrowser: FocusBrowser?
private var advanceFocus: AdvanceFocus?

private func report(_ event: String, token: UInt64, count: Int? = nil) {
    var record: [String: Any] = ["event": event, "token": token,
                                "mainThread": Thread.isMainThread]
    if let count { record["count"] = count }
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
        FileHandle.standardError.write(data + Data([10]))
    }
}

private final class SlotRoot: NSView {
    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Bato native slot controls" }
}

private final class Slot: NSObject, NSTextFieldDelegate {
    let token: UInt64
    let root = SlotRoot(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
    let field = NSTextField(string: "Native field")
    private let status = NSTextField(labelWithString: "Native action count: 0")
    private var count = 0

    init(token: UInt64) {
        self.token = token
        super.init()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.setAccessibilityIdentifier("bato-native-slot-root")
        let title = NSTextField(labelWithString: "Bato native slot")
        title.font = .boldSystemFont(ofSize: 16)
        field.setAccessibilityLabel("Bato native input")
        field.setAccessibilityIdentifier("bato-native-slot-input")
        field.delegate = self
        let action = NSButton(title: "Native action", target: self, action: #selector(clicked))
        action.setAccessibilityIdentifier("bato-native-slot-action")
        let focus = NSButton(title: "Focus browser", target: self, action: #selector(focusPage))
        let stack = NSStackView(views: [title, status, field, action, focus])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        report("slot-client-created", token: token)
    }

    @objc private func clicked() {
        count += 1
        status.stringValue = "Native action count: \(count)"
        report("slot-client-action", token: token, count: count)
    }

    @objc private func focusPage() {
        _ = focusBrowser?(token)
        report("slot-client-focus-browser-requested", token: token)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) ||
            commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            let reverse: Int32 = commandSelector == #selector(NSResponder.insertBacktab(_:)) ? 1 : 0
            let handled = advanceFocus?(token, reverse) == 1
            report("slot-client-focus-advance-requested", token: token, count: Int(reverse))
            return handled
        }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        // Neither entered text nor its length is logged or persisted.
        report("slot-client-input-edited", token: token)
    }
}

private var slots: [UInt64: Slot] = [:]

@_cdecl("BatoSwiftNativeSlotSetActions")
public func setActions(_ focus: @escaping @convention(c) (UInt64) -> Int32,
                       _ advance: @escaping @convention(c) (UInt64, Int32) -> Int32) {
    precondition(Thread.isMainThread)
    focusBrowser = focus
    advanceFocus = advance
}

@_cdecl("BatoSwiftNativeSlotCreate")
public func create(_ token: UInt64) -> UnsafeMutableRawPointer? {
    precondition(Thread.isMainThread)
    guard slots[token] == nil else { return nil }
    let slot = Slot(token: token)
    slots[token] = slot
    return Unmanaged.passUnretained(slot.root).toOpaque()
}

@_cdecl("BatoSwiftNativeSlotFocusTarget")
public func focusTarget(_ token: UInt64) -> UnsafeMutableRawPointer? {
    precondition(Thread.isMainThread)
    guard let slot = slots[token] else { return nil }
    return Unmanaged.passUnretained(slot.field).toOpaque()
}

@_cdecl("BatoSwiftNativeSlotDetached")
public func detached(_ token: UInt64) {
    precondition(Thread.isMainThread)
    guard slots.removeValue(forKey: token) != nil else { return }
    report("slot-client-detached", token: token, count: slots.count)
}
