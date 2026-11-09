import AppKit
import BatoCore

/// Arc's theme picker: a dotted colour field with draggable handles, light/dark modes, preset swatches,
/// a wavy strength slider and a grain dial. It edits a draft and reports every change as it happens.
@MainActor
final class SpaceThemePickerView: NSView {
    static let size = NSSize(width: 355, height: 506)

    private(set) var theme: SpaceTheme
    var onChange: ((SpaceTheme) -> Void)?
    private var selectedStop = 0
    private var presetPage = 0

    private let field = ThemeFieldView()
    private let modeButtons: [(SpaceTheme.Mode, NSButton)]
    private let remove = NSButton()
    private let add = NSButton()
    private let swatches = SwatchRow()
    private let slider = WaveSlider()
    private let dial = GrainDial()

    init(theme: SpaceTheme) {
        self.theme = theme
        modeButtons = [(.auto, "sparkles"), (.light, "sun.max"), (.dark, "moon")].map { mode, symbol in
            (mode, Self.symbolButton(symbol, size: 15, label: "\(mode.rawValue.capitalized) mode"))
        }
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        setAccessibilityIdentifier("bato-theme-picker")
        wantsLayer = true

        field.frame = NSRect(x: 7, y: 7, width: 340, height: 340)
        field.onTap = { [weak self] in self?.fieldTapped(at: $0) }
        field.onDrag = { [weak self] in self?.fieldDragged(to: $0) }
        field.onSelect = { [weak self] in self?.select($0) }
        addSubview(field)

        for (index, (mode, button)) in modeButtons.enumerated() {
            button.frame = NSRect(x: 120 + 40.5 * CGFloat(index), y: 32, width: 32, height: 30)
            button.target = self
            button.action = #selector(modeChosen(_:))
            button.tag = SpaceTheme.Mode.allCases.firstIndex(of: mode) ?? 0
            button.setAccessibilityIdentifier("bato-theme-mode-\(mode.rawValue)")
            addSubview(button)
        }
        for (button, symbol, label, x, action) in [(remove, "minus", "Remove colour", 147.0, #selector(removeStop)),
                                                   (add, "plus", "Add colour", 187.0, #selector(addStop))] {
            configure(button, symbol: symbol, label: label)
            button.frame = NSRect(x: x, y: 305, width: 20, height: 20)
            button.action = action
            addSubview(button)
        }
        addSubview(swatches)
        swatches.frame = NSRect(x: 7, y: 358, width: 340, height: 42)
        swatches.onPick = { [weak self] in self?.pick($0) }
        swatches.onPage = { [weak self] in self?.turnPage($0) }

        slider.frame = NSRect(x: 12, y: 416, width: 234, height: 72)
        slider.onChange = { [weak self] in self?.update { $0.intensity = $1 }($0) }
        addSubview(slider)
        dial.frame = NSRect(x: 252, y: 416, width: 88, height: 72)
        dial.onChange = { [weak self] in self?.update { $0.grain = $1 }($0) }
        addSubview(dial)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    override var isFlipped: Bool { true }

    private func update(_ change: @escaping (inout SpaceTheme, Double) -> Void) -> (Double) -> Void {
        { [weak self] value in
            guard let self else { return }
            change(&self.theme, value)
            self.refresh()
            self.onChange?(self.theme)
        }
    }

    private func configure(_ button: NSButton, symbol: String, label: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.image = image?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = NSColor.labelColor.withAlphaComponent(0.7)
        button.target = self
        button.setAccessibilityLabel(label)
    }

    private static func symbolButton(_ symbol: String, size: CGFloat, label: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.setAccessibilityLabel(label)
        return button
    }

    private func commit() {
        refresh()
        onChange?(theme)
    }

    private func refresh() {
        field.stops = theme.stops
        field.selected = selectedStop
        for (mode, button) in modeButtons {
            let on = mode == theme.mode
            button.layer?.backgroundColor = on ? NSColor.labelColor.withAlphaComponent(0.2).cgColor : nil
            button.contentTintColor = NSColor.labelColor.withAlphaComponent(on ? 0.95 : 0.6)
        }
        remove.isEnabled = theme.stops.count > 1
        add.isEnabled = theme.stops.count < SpaceTheme.maxStops
        remove.alphaValue = remove.isEnabled ? 1 : 0.35
        add.alphaValue = add.isEnabled ? 1 : 0.35
        swatches.page = presetPage
        slider.value = theme.intensity
        dial.value = theme.grain
    }

    // MARK: Actions

    @objc private func modeChosen(_ sender: NSButton) {
        theme.mode = SpaceTheme.Mode.allCases[sender.tag]
        commit()
    }

    @objc private func removeStop() {
        guard theme.removeStop(at: selectedStop) else { return }
        selectedStop = min(selectedStop, theme.stops.count - 1)
        commit()
    }

    @objc private func addStop() {
        guard theme.addStop() else { return }
        selectedStop = theme.stops.count - 1
        commit()
    }

    private func select(_ index: Int) {
        selectedStop = index
        refresh()
    }

    private func fieldTapped(at point: CGPoint) {
        theme.moveStop(at: selectedStop, toX: point.x, y: point.y)
        commit()
    }

    private func fieldDragged(to point: CGPoint) { fieldTapped(at: point) }

    private func pick(_ index: Int) {
        theme.stops = SpaceTheme.presetPages[presetPage][index].stops
        selectedStop = 0
        commit()
    }

    private func turnPage(_ delta: Int) {
        presetPage = min(max(presetPage + delta, 0), SpaceTheme.presetPages.count - 1)
        refresh()
    }
}

/// The dotted field. Positions are in the unit disc, y down.
@MainActor
private final class ThemeFieldView: NSView {
    var stops: [SpaceTheme.Stop] = [] { didSet { needsDisplay = true } }
    var selected = 0
    var onTap: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onSelect: ((Int) -> Void)?
    private var draggingHandle = false

    private var radius: CGFloat { bounds.width / 2 }
    override var isFlipped: Bool { true }

    private func point(for stop: SpaceTheme.Stop) -> CGPoint {
        CGPoint(x: bounds.midX + CGFloat(stop.x) * radius, y: bounds.midY + CGFloat(stop.y) * radius)
    }

    private func unit(_ location: CGPoint) -> CGPoint {
        CGPoint(x: (location.x - bounds.midX) / radius, y: (location.y - bounds.midY) / radius)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        for x in stride(from: CGFloat(4), to: bounds.width, by: 5) {
            for y in stride(from: CGFloat(4), to: bounds.height, by: 5) {
                NSBezierPath(ovalIn: NSRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4)).fill()
            }
        }
        if stops.isEmpty { return }
        for (index, stop) in stops.enumerated().sorted(by: { $0.offset == selected ? false : $1.offset == selected }) {
            drawHandle(stop, large: index == selected)
        }
    }

    private func drawHandle(_ stop: SpaceTheme.Stop, large: Bool) {
        let diameter: CGFloat = large ? 46 : 28
        let centre = point(for: stop)
        let rect = NSRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 4
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSGraphicsContext.restoreGraphicsState()
        let ring: CGFloat = large ? 3.5 : 2
        NSColor(hex: stop.color).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: ring, dy: ring)).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hit = stops.enumerated().min { hypot(point(for: $0.element).x - location.x, point(for: $0.element).y - location.y)
            < hypot(point(for: $1.element).x - location.x, point(for: $1.element).y - location.y) }
        if let hit, hypot(point(for: hit.element).x - location.x, point(for: hit.element).y - location.y) <= 24 {
            draggingHandle = true
            onSelect?(hit.offset)
        } else {
            draggingHandle = false
            onTap?(unit(location))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = unit(convert(event.locationInWindow, from: nil))
        if draggingHandle { onDrag?(location) } else { onTap?(location) }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Theme colour field" }
}

/// Nine swatches with arrows to page through the presets.
@MainActor
private final class SwatchRow: NSView {
    var page = 0 { didSet { needsDisplay = true } }
    var onPick: ((Int) -> Void)?
    var onPage: ((Int) -> Void)?
    override var isFlipped: Bool { true }

    private func swatchCentre(_ index: Int) -> CGPoint { CGPoint(x: 51 + 29.6 * CGFloat(index), y: bounds.midY) }

    override func draw(_ dirtyRect: NSRect) {
        let pages = SpaceTheme.presetPages
        for (symbol, x, enabled) in [("chevron.left", CGFloat(16), page > 0), ("chevron.right", CGFloat(324), page < pages.count - 1)] {
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold)) else { continue }
            image.isTemplate = true
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                NSColor.labelColor.withAlphaComponent(enabled ? 0.8 : 0.25).setFill()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(at: NSPoint(x: x - image.size.width / 2, y: bounds.midY - image.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
        }
        for (index, preset) in pages[page].enumerated() {
            let centre = swatchCentre(index)
            let rect = NSRect(x: centre.x - 12, y: centre.y - 12, width: 24, height: 24)
            let path = NSBezierPath(ovalIn: rect)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let colors = preset.stops.map { NSColor(hex: $0.color) }
            if colors.count > 1 { NSGradient(colors: colors)?.draw(in: rect, angle: -45) } else { colors[0].setFill(); rect.fill() }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if location.x < 34 { onPage?(-1); return }
        if location.x > 306 { onPage?(1); return }
        let index = Int(((location.x - 51) / 29.6).rounded())
        if (0..<9).contains(index), hypot(swatchCentre(index).x - location.x, swatchCentre(index).y - location.y) <= 15 { onPick?(index) }
    }
}

/// A sine track whose swing and thumb grow with the value.
@MainActor
private final class WaveSlider: NSView {
    var value = 0.5 { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?
    override var isFlipped: Bool { true }
    private let inset: CGFloat = 36
    private var travel: ClosedRange<CGFloat> { inset...(bounds.width - inset) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 6, y: bounds.midY - 8, width: bounds.width - 12, height: 16)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: track, xRadius: 8, yRadius: 8).fill()
        let wave = NSBezierPath()
        let amplitude = 2 + 15 * CGFloat(value)
        for x in stride(from: track.minX + 4, through: track.maxX - 4, by: 1) {
            let point = NSPoint(x: x, y: bounds.midY + sin((x - track.minX) / 28 * 2 * .pi) * amplitude * ((x - track.minX) / track.width * 0.6 + 0.4))
            if x == track.minX + 4 { wave.move(to: point) } else { wave.line(to: point) }
        }
        wave.lineWidth = 3
        wave.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        wave.stroke()
        let width = 16 + 12 * CGFloat(value), height = 52 + 10 * CGFloat(value)
        let x = travel.lowerBound + (travel.upperBound - travel.lowerBound) * CGFloat(value)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 4
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: x - width / 2, y: bounds.midY - height / 2, width: width, height: height),
                     xRadius: width / 2, yRadius: width / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func set(from event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        onChange?(Double(min(max((x - travel.lowerBound) / (travel.upperBound - travel.lowerBound), 0), 1)))
    }
    override func mouseDown(with event: NSEvent) { set(from: event) }
    override func mouseDragged(with event: NSEvent) { set(from: event) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Theme strength" }
    override func accessibilityValue() -> Any? { value }
}

/// A ring of dots that fill clockwise from the top as the grain grows.
@MainActor
private final class GrainDial: NSView {
    var value = 0.0 { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?
    override var isFlipped: Bool { true }
    private static let dots = 28

    override func draw(_ dirtyRect: NSRect) {
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        for index in 0..<Self.dots {
            let fraction = Double(index) / Double(Self.dots)
            let angle = CGFloat(fraction) * 2 * .pi - .pi / 2
            let filled = fraction < value
            NSColor.labelColor.withAlphaComponent(filled ? 0.7 : 0.22).setFill()
            let dot = NSPoint(x: centre.x + cos(angle) * 33, y: centre.y + sin(angle) * 33)
            NSBezierPath(ovalIn: NSRect(x: dot.x - 1.3, y: dot.y - 1.3, width: 2.6, height: 2.6)).fill()
        }
        NSColor.labelColor.withAlphaComponent(0.1 + 0.2 * CGFloat(value)).setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - 20, y: centre.y - 20, width: 40, height: 40)).fill()
        NSColor.labelColor.withAlphaComponent(0.2).setStroke()
        let outline = NSBezierPath(ovalIn: NSRect(x: centre.x - 20, y: centre.y - 20, width: 40, height: 40))
        outline.lineWidth = 1
        outline.stroke()
        let angle = CGFloat(value) * 2 * .pi - .pi / 2
        NSGraphicsContext.saveGraphicsState()
        var transform = AffineTransform(translationByX: centre.x + cos(angle) * 33, byY: centre.y + sin(angle) * 33)
        transform.rotate(byRadians: angle + .pi / 2)
        let pill = NSBezierPath(roundedRect: NSRect(x: -2, y: -6, width: 4, height: 12), xRadius: 2, yRadius: 2)
        pill.transform(using: transform)
        NSColor.white.setFill()
        pill.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func set(from event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        var turns = Double(atan2(location.y - bounds.midY, location.x - bounds.midX) + .pi / 2) / (2 * .pi)
        if turns < 0 { turns += 1 }
        onChange?(turns > 0.985 ? 1 : turns)
    }
    override func mouseDown(with event: NSEvent) { set(from: event) }
    override func mouseDragged(with event: NSEvent) { set(from: event) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Grain" }
    override func accessibilityValue() -> Any? { value }
}

/// Hosts the picker in a callout popover anchored to the row that opened it.
@MainActor
final class SpaceThemePopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let picker: SpaceThemePickerView
    private var onClose: ((SpaceTheme) -> Void)?

    init(theme: SpaceTheme, onChange: @escaping (SpaceTheme) -> Void, onClose: @escaping (SpaceTheme) -> Void) {
        picker = SpaceThemePickerView(theme: theme)
        self.onClose = onClose
        super.init()
        picker.onChange = { [weak self] in
            self?.popover.appearance = $0.appearance
            onChange($0)
        }
        let controller = NSViewController()
        controller.view = picker
        popover.contentViewController = controller
        popover.contentSize = SpaceThemePickerView.size
        popover.behavior = .semitransient
        popover.animates = true
        popover.appearance = theme.appearance
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        onClose?(picker.theme)
        onClose = nil
    }
}
