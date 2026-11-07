import AppKit
import BatoCore

/// The Archive list: search the current Profile's archived tabs, restore one or delete it.
/// Restoring reopens the tab in its original workspace.
@MainActor
final class ArchiveSheet: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let searchField = NSSearchField(string: "")
    private let table = ArchiveTable()
    private let countLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let restoreButton = NSButton(title: "Restore", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let records: (String) -> [ArchiveRecord]
    private let workspaceName: (UUID) -> String?
    private let restore: (UUID) -> String?
    private let delete: (UUID) -> String?
    private let now: () -> Date
    private var rows: [ArchiveRecord] = []

    /// `restore` and `delete` return an error message, or nil when they succeeded.
    init(records: @escaping (String) -> [ArchiveRecord], workspaceName: @escaping (UUID) -> String?,
         restore: @escaping (UUID) -> String?, delete: @escaping (UUID) -> String?,
         now: @escaping () -> Date = { Date() }) {
        self.records = records
        self.workspaceName = workspaceName
        self.restore = restore
        self.delete = delete
        self.now = now
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Archive"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildLayout(panel)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    func refresh() {
        let selectedID = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        rows = records(searchField.stringValue)
        table.reloadData()
        if let index = rows.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !rows.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateButtons()
        let searching = !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        countLabel.stringValue = rows.isEmpty
            ? (searching ? "No archived tabs match." : "Nothing is archived yet. Tabs you don’t use move here.")
            : "\(rows.count) archived \(rows.count == 1 ? "tab" : "tabs")"
    }

    private func buildLayout(_ panel: NSPanel) {
        searchField.placeholderString = "Search archived tabs"
        searchField.setAccessibilityLabel("Search archived tabs")
        searchField.setAccessibilityIdentifier("bato-archive-search")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.cell?.sendsActionOnEndEditing = false
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 52
        table.backgroundColor = .clear
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.selectionHighlightStyle = .regular
        table.setAccessibilityLabel("Archived tabs")
        table.setAccessibilityIdentifier("bato-archive-results")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("archived"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(restoreSelected)
        table.restoreSelection = { [weak self] in self?.restoreSelected() }
        table.cancel = { [weak self] in self?.dismiss(.cancel) }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = table
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setAccessibilityIdentifier("bato-archive-count")
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityIdentifier("bato-archive-error")
        let done = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\u{1b}"
        done.setAccessibilityIdentifier("bato-archive-done")
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.setAccessibilityIdentifier("bato-archive-delete")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)
        restoreButton.keyEquivalent = "\r"
        restoreButton.setAccessibilityIdentifier("bato-archive-restore")
        panel.defaultButtonCell = restoreButton.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [deleteButton, spacer, done, restoreButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [searchField, countLabel, scroll, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = panel.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func updateButtons() {
        let hasSelection = rows.indices.contains(table.selectedRow)
        restoreButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }

    func controlTextDidChange(_ notification: Notification) {
        errorLabel.stringValue = ""
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): restoreSelected()
        case #selector(NSResponder.cancelOperation(_:)): dismiss(.cancel)
        default: return false
        }
        return true
    }

    private func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let row = max(0, min(rows.count - 1, table.selectedRow + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RoundedRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let record = rows[row]
        let title = NSTextField(labelWithString: record.title.isEmpty ? record.url.absoluteString : record.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let place = workspaceName(record.workspaceID).map { "\($0) · " } ?? ""
        let detail = NSTextField(labelWithString: "\(place)\(record.url.absoluteString)")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        let age = NSTextField(labelWithString: Self.relativeAge(of: record.archivedAt, to: now()))
        age.font = .systemFont(ofSize: 12)
        age.textColor = .tertiaryLabelColor
        age.setContentHuggingPriority(.required, for: .horizontal)
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let line = NSStackView(views: [text, age])
        line.spacing = 10
        line.alignment = .centerY
        line.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.textField = title
        cell.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            line.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            line.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    static func relativeAge(of date: Date, to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    @objc private func restoreSelected() {
        guard rows.indices.contains(table.selectedRow) else { return }
        if let error = restore(rows[table.selectedRow].id) {
            errorLabel.stringValue = error
        } else {
            dismiss(.OK)
        }
    }

    @objc private func deleteSelected() {
        guard rows.indices.contains(table.selectedRow) else { return }
        if let error = delete(rows[table.selectedRow].id) {
            errorLabel.stringValue = error
        } else {
            refresh()
        }
    }

    @objc private func done(_ sender: Any?) { dismiss(.cancel) }

    private func dismiss(_ response: NSApplication.ModalResponse) {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window, returnCode: response)
        window.orderOut(nil)
    }
}

@MainActor
private final class ArchiveTable: NSTableView {
    var restoreSelection: (() -> Void)?
    var cancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: restoreSelection?()
        case 53: cancel?()
        default: super.keyDown(with: event)
        }
    }
}
