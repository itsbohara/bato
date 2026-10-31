import AppKit
import BatoCore

/// A native modal surface: Chromium retains ownership of the parent window and
/// its sheet lifecycle. No page or network work happens while the user types.
@MainActor
final class CommandBarController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let field = NSSearchField(string: "")
    private let providerPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private var provider: CommandBarSearchProvider
    private let providerChanged: (CommandBarSearchProvider) -> Void
    private let table = CommandBarTable()
    private let hint = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
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
        let panel = CommandBarPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 410),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "New Tab"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init(window: panel)
        let surface = CommandBarSurface()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 16
        surface.layer?.masksToBounds = true
        panel.contentView = surface
        field.stringValue = query
        field.placeholderString = "Search or enter a URL"
        field.font = .systemFont(ofSize: 20)
        field.controlSize = .large
        field.focusRingType = .none
        field.setAccessibilityLabel("Command bar search or address")
        field.setAccessibilityIdentifier("bato-command-bar-input")
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.cell?.sendsActionOnEndEditing = false
        providerPicker.addItems(withTitles: CommandBarSearchProvider.allCases.map(\.title))
        if let index = CommandBarSearchProvider.allCases.firstIndex(of: provider) { providerPicker.selectItem(at: index) }
        providerPicker.target = self
        providerPicker.action = #selector(changeProvider)
        providerPicker.setAccessibilityLabel("Web search provider")
        providerPicker.setAccessibilityIdentifier("bato-command-bar-provider")
        providerPicker.toolTip = "Search provider for this session"
        let inputRow = NSStackView(views: [field, providerPicker])
        inputRow.spacing = 12
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        providerPicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 52
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
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelBar))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier("bato-command-bar-cancel")
        openButton.target = self
        openButton.action = #selector(openSelected)
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"
        openButton.setAccessibilityIdentifier("bato-command-bar-open")
        panel.defaultButtonCell = openButton.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [hint, spacer, cancel, openButton])
        footer.spacing = 8
        let divider = NSBox()
        divider.boxType = .separator
        let stack = NSStackView(views: [inputRow, divider, scroll, errorLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -16),
            inputRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            field.heightAnchor.constraint(equalToConstant: 36),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
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
        results = resultsForQuery(field.stringValue)
        table.reloadData()
        if let index = results.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !results.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        openButton.isEnabled = results.indices.contains(table.selectedRow)
        if case .invalid(let message) = CommandBarInput.resolve(field.stringValue, provider: provider) {
            hint.stringValue = message
        } else {
            hint.stringValue = "↑↓ to choose · Return to open · Esc to cancel"
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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let result = results[row]
        let symbol: String
        switch result.action {
        case .open: symbol = "arrow.up.right"
        case .activate: symbol = "rectangle.on.rectangle"
        case .command: symbol = "command"
        }
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: result.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: result.subtitle)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let rowView = NSStackView(views: [image, labels])
        rowView.spacing = 12
        rowView.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.textField = title
        cell.addSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            rowView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            rowView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 20),
            title.widthAnchor.constraint(equalTo: labels.widthAnchor),
            detail.widthAnchor.constraint(equalTo: labels.widthAnchor)
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

@MainActor
private final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
    override func updateLayer() { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
