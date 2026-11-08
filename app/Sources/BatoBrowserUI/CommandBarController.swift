import AppKit
import BatoCore

/// A native modal surface: Chromium retains ownership of the parent window and
/// its sheet lifecycle. No page or network work happens while the user types.
@MainActor
final class CommandBarController: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let field = NSTextField(string: "")
    private let glyph = NSImageView()
    private var provider: CommandBarSearchProvider
    private let table = CommandBarTable()
    private let scroll = NSScrollView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private var listHeight: NSLayoutConstraint!
    private var refreshedQuery = ""
    private let resultsForQuery: (String) -> [CommandBarResult]
    private let pageIcon: (UUID) -> NSImage?
    private var results: [CommandBarResult] = []
    private(set) var chosenAction: CommandBarAction?
    var query: String { field.stringValue }

    init(query: String = "", error: String? = nil,
         provider: CommandBarSearchProvider = .duckDuckGo,
         pageIcon: @escaping (UUID) -> NSImage? = { _ in nil },
         results: @escaping (String) -> [CommandBarResult]) {
        self.provider = provider
        self.pageIcon = pageIcon
        resultsForQuery = results
        let panel = CommandBarPanel(contentRect: NSRect(x: 0, y: 0, width: SidebarStyle.commandBarWidth, height: 300),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "New Tab"
        panel.initialFirstResponder = field
        panel.searchField = field
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init(window: panel)
        let surface = CommandBarSurface()
        panel.contentView = surface
        field.stringValue = query
        field.font = .systemFont(ofSize: 19, weight: .medium)
        field.placeholderAttributedString = NSAttributedString(string: "Search or Enter URL...", attributes: [
            .font: NSFont.systemFont(ofSize: 19, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.setAccessibilityLabel("Command bar search or address")
        field.setAccessibilityIdentifier("bato-command-bar-input")
        field.delegate = self
        field.cell?.sendsActionOnEndEditing = false
        glyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: 18, weight: .medium)
        glyph.contentTintColor = .secondaryLabelColor
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for view in [glyph, field] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        let separator = NSBox()
        separator.boxType = .separator
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = SidebarStyle.commandBarRowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.setAccessibilityLabel("Command bar results")
        table.setAccessibilityIdentifier("bato-command-bar-results")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.openSelection = { [weak self] in self?.openSelected() }
        table.cancel = { [weak self] in self?.dismiss(.cancel) }
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let listHost = NSView()
        listHost.translatesAutoresizingMaskIntoConstraints = false
        listHost.addSubview(scroll)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.setAccessibilityIdentifier("bato-command-bar-hint")
        if let error, !error.isEmpty { status.stringValue = error; status.textColor = .systemRed }
        let statusHost = NSView()
        statusHost.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        statusHost.addSubview(status)
        stack.setViews([header, separator, listHost, statusHost], in: .top)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        listHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        let inset = SidebarStyle.commandBarInset
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            stack.topAnchor.constraint(equalTo: surface.topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            header.heightAnchor.constraint(equalToConstant: SidebarStyle.commandBarHeaderHeight),
            glyph.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            glyph.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 22),
            field.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            field.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            listHost.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.leadingAnchor.constraint(equalTo: listHost.leadingAnchor, constant: inset),
            scroll.trailingAnchor.constraint(equalTo: listHost.trailingAnchor, constant: -inset),
            scroll.topAnchor.constraint(equalTo: listHost.topAnchor, constant: inset),
            scroll.bottomAnchor.constraint(equalTo: listHost.bottomAnchor, constant: -inset),
            listHeight,
            statusHost.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.leadingAnchor.constraint(equalTo: statusHost.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: statusHost.trailingAnchor, constant: -20),
            status.topAnchor.constraint(equalTo: statusHost.topAnchor),
            status.bottomAnchor.constraint(equalTo: statusHost.bottomAnchor, constant: -10)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    func focusSearch() {
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    func refresh() {
        let selectedID = results.indices.contains(table.selectedRow) ? results[table.selectedRow].id : nil
        let query = field.stringValue
        results = resultsForQuery(query)
        table.reloadData()
        if let row = CommandBarSelection.rowAfterRefresh(previousID: selectedID, previousQuery: refreshedQuery,
                                                         query: query, results: results) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        refreshedQuery = query
        if case .invalid(let message) = CommandBarInput.resolve(field.stringValue, provider: provider) {
            status.stringValue = message
            status.textColor = .secondaryLabelColor
        } else if status.textColor == .secondaryLabelColor {
            status.stringValue = ""
        }
        fitToResults()
    }

    /// The panel hugs its rows, as Arc's does. Resizing a sheet re-centres it, so the top edge is pinned back.
    private func fitToResults() {
        listHeight.constant = CGFloat(min(results.count, SidebarStyle.commandBarMaxRows)) * SidebarStyle.commandBarRowHeight
        status.superview?.isHidden = status.stringValue.isEmpty
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let height = ceil(stack.fittingSize.height)
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: SidebarStyle.commandBarWidth, height: height))
        window.setFrameTopLeftPoint(topLeft)
    }

    func controlTextDidChange(_ notification: Notification) {
        if status.textColor == .systemRed { status.stringValue = ""; status.textColor = .secondaryLabelColor }
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        case #selector(NSResponder.cancelOperation(_:)): dismiss(.cancel)
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
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaletteRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let result = results[row]
        let symbol: String
        var detail = ""
        var trailing = "Open"
        var selectedTrailing = "Open"
        var image: NSImage?
        switch result.action {
        case .open(let url): symbol = result.subtitle == "Web search" ? "magnifyingglass" : "globe"; detail = result.subtitle == "Web search" ? "" : url.absoluteString
        case .navigateCurrent(let url): symbol = result.subtitle == "Web search" ? "magnifyingglass" : "globe"; detail = result.subtitle == "Web search" ? "" : url.absoluteString; trailing = "Go"; selectedTrailing = "Go"
        case .peek(let url): symbol = "rectangle.center.inset.filled"; detail = url.absoluteString; trailing = "Peek"; selectedTrailing = "Peek"
        case .activate(let page):
            symbol = "rectangle.on.rectangle"
            detail = page.entry.lastURL.absoluteString
            trailing = page.workspaceName.uppercased()
            selectedTrailing = "Switch to Tab"
            image = pageIcon(page.entryID) ?? SidebarStyle.letterIcon(for: page.entry.title, url: page.entry.lastURL, size: 16)
        case .command: symbol = "command"; trailing = "Command"; selectedTrailing = "Run"
        }
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        let cell = PaletteCell(result: result, icon: image ?? symbolImage ?? NSImage(), iconIsSymbol: image == nil,
                               detail: detail, unselectedTrailing: trailing, selectedTrailing: selectedTrailing)
        return cell
    }

    @objc private func openSelected() {
        guard results.indices.contains(table.selectedRow) else { return }
        chosenAction = results[table.selectedRow].action
        dismiss(.OK)
    }
    private func dismiss(_ response: NSApplication.ModalResponse) {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window, returnCode: response)
        window.orderOut(nil)
    }
}

@MainActor
private final class CommandBarPanel: NSPanel {
    weak var searchField: NSTextField?
    private var focusedOnFirstKey = false
    override var canBecomeKey: Bool { true }
    /// A sheet becomes key after beginSheet returns, which can reset the first responder set
    /// before then; Return would then reach neither the field nor the default button.
    override func becomeKey() {
        super.becomeKey()
        guard !focusedOnFirstKey, let searchField else { return }
        focusedOnFirstKey = true
        makeFirstResponder(searchField)
        searchField.selectText(nil)
    }
}

@MainActor
private final class CommandBarTable: NSTableView {
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

/// Translucent panel: vibrancy under a dark or light tint so the page stays faintly visible around and behind it.
@MainActor
private final class CommandBarSurface: NSVisualEffectView {
    private let tint = CommandBarTint()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = SidebarStyle.commandBarRadius
        layer?.masksToBounds = true
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor(name: nil) {
            $0.isDark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.12)
        }.cgColor
        layer?.borderWidth = 1
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: AppearanceWatcher.didChange, object: nil)
        }
    }
    @objc private func refresh() { needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        tint.needsDisplay = true
    }
}

@MainActor
private final class CommandBarTint: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (effectiveAppearance.isDark
                ? NSColor(srgbRed: 0.098, green: 0.098, blue: 0.106, alpha: 0.9)
                : NSColor.white.withAlphaComponent(0.72)).cgColor
        }
    }
}

/// Selected row: a saturated indigo pill, as in Arc, in both appearances.
@MainActor
private final class PaletteRowView: NSTableRowView {
    static let accent = NSColor(srgbRed: 0.357, green: 0.357, blue: 0.839, alpha: 1)
    override var isEmphasized: Bool { get { true } set {} }
    override var isSelected: Bool {
        didSet { (subviews.first as? PaletteCell)?.apply(selected: isSelected) }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        Self.accent.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
    override func addSubview(_ view: NSView) {
        super.addSubview(view)
        (view as? PaletteCell)?.apply(selected: isSelected)
    }
}

@MainActor
private final class PaletteCell: NSTableCellView {
    private let icon = NSImageView()
    private let detail = NSTextField(labelWithString: "")
    private let trailing = NSTextField(labelWithString: "")
    private let arrowBox = NSView()
    private let arrow = NSImageView()
    private let unselectedTrailing: String
    private let selectedTrailing: String
    private let iconIsSymbol: Bool

    init(result: CommandBarResult, icon image: NSImage, iconIsSymbol: Bool, detail text: String,
         unselectedTrailing: String, selectedTrailing: String) {
        self.unselectedTrailing = unselectedTrailing
        self.selectedTrailing = selectedTrailing
        self.iconIsSymbol = iconIsSymbol
        super.init(frame: .zero)
        icon.image = image
        icon.imageScaling = .scaleProportionallyDown
        let title = NSTextField(labelWithString: result.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        textField = title
        detail.stringValue = text
        detail.font = .systemFont(ofSize: 13)
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing.font = .systemFont(ofSize: 12, weight: .semibold)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrowBox.wantsLayer = true
        arrowBox.layer?.cornerRadius = 5
        arrowBox.translatesAutoresizingMaskIntoConstraints = false
        arrowBox.addSubview(arrow)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [icon, title, detail, spacer, trailing, arrowBox])
        row.spacing = 10
        row.setCustomSpacing(12, after: spacer)
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            arrowBox.widthAnchor.constraint(equalToConstant: 22),
            arrowBox.heightAnchor.constraint(equalToConstant: 22),
            arrow.centerXAnchor.constraint(equalTo: arrowBox.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: arrowBox.centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func apply(selected: Bool) {
        textField?.textColor = selected ? .white : .labelColor
        detail.textColor = selected ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor
        trailing.stringValue = selected ? selectedTrailing : unselectedTrailing
        trailing.textColor = selected ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
        if iconIsSymbol { icon.contentTintColor = selected ? .white : .secondaryLabelColor }
        let arrowColor = selected ? PaletteRowView.accent : NSColor.secondaryLabelColor
        arrow.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold).applying(.init(paletteColors: [arrowColor])))
        effectiveAppearance.performAsCurrentDrawingAppearance {
            arrowBox.layer?.backgroundColor = (selected ? NSColor.white : NSColor.labelColor.withAlphaComponent(0.08)).cgColor
        }
    }
}
