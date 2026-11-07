import AppKit
import BatoCore

/// A native modal surface: Chromium retains ownership of the parent window and
/// its sheet lifecycle. No page or network work happens while the user types.
@MainActor
final class CommandBarController: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let field = NSTextField(string: "")
    private let glyph = NSImageView()
    private let providerPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private var provider: CommandBarSearchProvider
    private let providerChanged: (CommandBarSearchProvider) -> Void
    private let table = CommandBarTable()
    private let hint = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = GoPillButton()
    private var refreshedQuery = ""
    private let resultsForQuery: (String) -> [CommandBarResult]
    private var results: [CommandBarResult] = []
    private(set) var chosenAction: CommandBarAction?
    var query: String { field.stringValue }

    init(query: String = "", error: String? = nil,
         provider: CommandBarSearchProvider = .duckDuckGo,
         providerChanged: @escaping (CommandBarSearchProvider) -> Void,
         results: @escaping (String) -> [CommandBarResult]) {
        self.provider = provider
        self.providerChanged = providerChanged
        resultsForQuery = results
        let panel = CommandBarPanel(contentRect: NSRect(origin: .zero, size: SidebarStyle.commandBarSize),
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
        surface.wantsLayer = true
        surface.layer?.cornerRadius = SidebarStyle.commandBarRadius
        surface.layer?.borderWidth = 0.5
        surface.layer?.masksToBounds = true
        panel.contentView = surface
        field.stringValue = query
        field.placeholderString = "Search or enter a URL"
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.controlSize = .large
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.setAccessibilityLabel("Command bar search or address")
        field.setAccessibilityIdentifier("bato-command-bar-input")
        field.delegate = self
        field.cell?.sendsActionOnEndEditing = false
        glyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        glyph.contentTintColor = .secondaryLabelColor
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        providerPicker.addItems(withTitles: CommandBarSearchProvider.allCases.map(\.title))
        if let index = CommandBarSearchProvider.allCases.firstIndex(of: provider) { providerPicker.selectItem(at: index) }
        providerPicker.target = self
        providerPicker.action = #selector(changeProvider)
        providerPicker.setAccessibilityLabel("Web search provider")
        providerPicker.setAccessibilityIdentifier("bato-command-bar-provider")
        providerPicker.toolTip = "Search provider for this session"
        providerPicker.isBordered = false
        providerPicker.controlSize = .small
        providerPicker.font = .systemFont(ofSize: 12)
        let inputRow = NSStackView(views: [glyph, field])
        inputRow.spacing = 10
        inputRow.alignment = .centerY
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = SidebarStyle.commandBarRowHeight
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
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.setAccessibilityIdentifier("bato-command-bar-hint")
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.stringValue = error ?? ""
        errorLabel.setAccessibilityIdentifier("bato-command-bar-error")
        openButton.target = self
        openButton.action = #selector(openSelected)
        openButton.keyEquivalent = "\r"
        openButton.setAccessibilityLabel("Go")
        openButton.setAccessibilityIdentifier("bato-command-bar-open")
        panel.defaultButtonCell = openButton.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [providerPicker, hint, spacer, openButton])
        footer.spacing = 12
        footer.alignment = .centerY
        let divider = NSBox()
        divider.boxType = .separator
        let stack = NSStackView(views: [inputRow, divider, scroll, errorLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -18),
            inputRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            field.heightAnchor.constraint(equalToConstant: 40),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
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
        openButton.isEnabled = results.indices.contains(table.selectedRow)
        if case .invalid(let message) = CommandBarInput.resolve(field.stringValue, provider: provider) {
            hint.stringValue = message
        } else {
            hint.stringValue = "↑↓ choose · Esc cancel"
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        errorLabel.stringValue = ""
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
    func tableViewSelectionDidChange(_ notification: Notification) {
        openButton.isEnabled = results.indices.contains(table.selectedRow)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RoundedRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let result = results[row]
        let symbol: String
        switch result.action {
        case .open: symbol = "arrow.up.right"
        case .navigateCurrent: symbol = "arrow.right"
        case .peek: symbol = "rectangle.center.inset.filled"
        case .activate: symbol = "rectangle.on.rectangle"
        case .command: symbol = "command"
        }
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        image.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: result.title)
        title.font = .systemFont(ofSize: 15)
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: result.subtitle)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        let rowView = NSStackView(views: [image, title, detail])
        rowView.spacing = 10
        rowView.alignment = .firstBaseline
        rowView.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.textField = title
        cell.addSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            rowView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            rowView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 20)
        ])
        return cell
    }

    @objc private func changeProvider() {
        let choices = CommandBarSearchProvider.allCases
        guard choices.indices.contains(providerPicker.indexOfSelectedItem) else { return }
        provider = choices[providerPicker.indexOfSelectedItem]
        providerChanged(provider)
        refresh()
    }

    @objc private func cancelBar() { dismiss(.cancel) }
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

/// The "Go" pill: a light capsule with dark text, as in Dia, instead of a stock push button.
@MainActor
private final class GoPillButton: NSButton {
    init() {
        super.init(frame: .zero)
        title = "Go  ⏎"
        isBordered = false
        font = .systemFont(ofSize: 15, weight: .semibold)
        wantsLayer = true
        layer?.cornerRadius = 15
        focusRingType = .none
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        widthAnchor.constraint(equalToConstant: 78).isActive = true
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    override func viewDidChangeEffectiveAppearance() { refreshColors() }
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.88).cgColor
            attributedTitle = NSAttributedString(string: title, attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.windowBackgroundColor])
        }
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

@MainActor
private final class CommandBarSurface: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
