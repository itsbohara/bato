import AppKit
import BatoCore
import BatoImport
import BatoPersistence
import BatoRuntime
import UniformTypeIdentifiers

/// Arc import flow: the user picks a file, previews the result, and applies it as one saved change.
/// Arc's own files are only read after the user chooses one; nothing is ever written to them.
@MainActor
final class ArcImportController {
    private let window: NSWindow
    private let store: OrganizationStore<BrowserState>
    private let runtime: PageRuntime
    private let finished: () -> Void
    private var sheet: ArcImportSheet?

    init(window: NSWindow, store: OrganizationStore<BrowserState>, runtime: PageRuntime,
         finished: @escaping () -> Void) {
        self.window = window
        self.store = store
        self.runtime = runtime
        self.finished = finished
    }

    func begin() {
        let panel = NSOpenPanel()
        panel.title = "Import from Arc"
        panel.message = "Choose Arc’s StorableSidebar.json, or a copy of it. Bato only reads this file."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = ArcSourceReader.defaultDirectory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { return self.finished() }
            self.load(url)
        }
    }

    private func load(_ url: URL) {
        Task { [weak self] in
            let result = await Task.detached { () -> Result<ArcStaging, Error> in
                Result { try ArcSidebarParser.parse(ArcSourceReader.read(url).data) }
            }.value
            guard let self else { return }
            switch result {
            case .success(let staging): self.present(staging)
            case .failure(let error): self.showFailure(error)
            }
        }
    }

    private func showFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Arc import couldn’t read this file"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? "The file could not be read."
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { [weak self] _ in self?.finished() }
    }

    private func present(_ staging: ArcStaging) {
        let sheet = ArcImportSheet(staging: staging, state: { [runtime] in runtime.state },
                                   apply: { [weak self] plan in self?.apply(plan) ?? .failure(.unavailable) },
                                   undo: { [weak self] applied in self?.undo(applied) ?? .failure(.unavailable) })
        self.sheet = sheet
        guard let panel = sheet.window else { return finished() }
        window.beginSheet(panel) { [weak self] _ in
            self?.sheet = nil
            self?.finished()
        }
    }

    private func apply(_ plan: ImportPlan) -> Result<ImportTransaction.Applied, ArcImportFailure> {
        let applied: ImportTransaction.Applied
        do { applied = try ImportTransaction.apply(plan, to: store) }
        catch let error as OrganizationStore<BrowserState>.StoreError {
            return .failure(error == .conflict ? .changedElsewhere : .notSaved)
        } catch { return .failure(.notSaved) }
        guard runtime.adoptSavedOrganization(applied.state) else {
            _ = try? ImportTransaction.undo(applied, in: store)
            return .failure(.notSaved)
        }
        return .success(applied)
    }

    private func undo(_ applied: ImportTransaction.Applied) -> Result<Void, ArcImportFailure> {
        do {
            let restored = try ImportTransaction.undo(applied, in: store)
            guard runtime.adoptSavedOrganization(restored) else { return .failure(.notSaved) }
            return .success(())
        } catch let error as OrganizationStore<BrowserState>.StoreError {
            return .failure(error == .snapshotStale || error == .conflict ? .changedSinceImport : .notSaved)
        } catch { return .failure(.notSaved) }
    }
}

enum ArcImportFailure: Error {
    case unavailable
    case notSaved
    case changedElsewhere
    case changedSinceImport

    var message: String {
        switch self {
        case .unavailable: "Import is no longer available."
        case .notSaved: "Changes couldn’t be saved. Nothing was changed."
        case .changedElsewhere: "Bato’s organization changed outside this window. Reopen Bato, then import again."
        case .changedSinceImport:
            "Bato has changed since the import, so it can’t be undone safely. Delete the imported workspaces instead."
        }
    }
}

@MainActor
private final class ArcImportSheet: NSWindowController {
    private let staging: ArcStaging
    private let currentState: () -> BrowserState
    private let apply: (ImportPlan) -> Result<ImportTransaction.Applied, ArcImportFailure>
    private let undo: (ImportTransaction.Applied) -> Result<Void, ArcImportFailure>

    private var included: Set<String>
    private var includeToday = false
    private var importAgain = false
    private var applied: ImportTransaction.Applied?

    private let content = NSStackView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var spaceBoxes: [(id: String, box: NSButton)] = []
    private let totals = NSTextField(wrappingLabelWithString: "")
    private let unsupported = NSTextField(wrappingLabelWithString: "")
    private var importButton: NSButton?

    init(staging: ArcStaging, state: @escaping () -> BrowserState,
         apply: @escaping (ImportPlan) -> Result<ImportTransaction.Applied, ArcImportFailure>,
         undo: @escaping (ImportTransaction.Applied) -> Result<Void, ArcImportFailure>) {
        self.staging = staging
        currentState = state
        self.apply = apply
        self.undo = undo
        included = Set(staging.spaces.map(\.id))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Import from Arc"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        guard let view = panel.contentView else { return }
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        showPreview()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: Preview

    private var salt: String { importAgain ? "copy-\(staging.sourceDigest.prefix(8))-\(UUID().uuidString.prefix(8))" : "" }

    private var alreadyImported: Set<String> {
        ImportPlan.alreadyImportedSpaceIDs(staging, in: currentState())
    }

    /// Spaces that would actually be imported: checked, and not already imported unless copies were requested.
    private var selected: Set<String> {
        ImportPlan.spacesToImport(checked: included, alreadyImported: alreadyImported, asCopies: importAgain)
    }

    private func options(salt: String = "") -> ImportOptions {
        ImportOptions(includeTodayTabs: includeToday,
                      excludedSpaceIDs: Set(staging.spaces.map(\.id)).subtracting(selected), idSalt: salt)
    }

    private func showPreview() {
        spaceBoxes = []
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let counts = (try? ImportPlan.make(staging, options: ImportOptions(includeTodayTabs: includeToday),
                                           into: .initial()))?.summary
        let done = alreadyImported

        add(label("Import from Arc", size: 15, weight: .semibold))
        add(label("Choose what to bring into Bato. Arc isn’t modified, and passwords, logins and cookies aren’t imported. " +
                  "Each Arc profile becomes a new Bato Profile.", secondary: true))

        let rows = TopAlignedStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        for space in staging.spaces {
            let alreadyThere = done.contains(space.id) && !importAgain
            let box = NSButton(checkboxWithTitle: space.title, target: nil, action: nil)
            box.state = included.contains(space.id) && !alreadyThere ? .on : .off
            box.isEnabled = !alreadyThere
            box.setAccessibilityLabel("Import space \(space.title)")
            box.setAccessibilityIdentifier("bato-arc-import-space")
            ClosureTarget.attach(to: box) { [weak self] in
                guard let self else { return }
                if box.state == .on { self.included.insert(space.id) } else { self.included.remove(space.id) }
                self.refreshSummary()
            }
            spaceBoxes.append((space.id, box))
            let detail = alreadyThere ? "Already imported from this file" : describe(counts?.spaces.first { $0.arcID == space.id })
            let text = label(detail, secondary: true)
            text.setAccessibilityLabel("\(space.title): \(detail)")
            let row = NSStackView(views: [box, text])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 1
            text.setContentHuggingPriority(.defaultLow, for: .horizontal)
            text.preferredMaxLayoutWidth = 400
            rows.addArrangedSubview(row)
            if let leading = text.superview { text.leadingAnchor.constraint(equalTo: leading.leadingAnchor, constant: 18).isActive = true }
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .lineBorder
        scroll.documentView = rows
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setAccessibilityLabel("Arc spaces")
        add(scroll)
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor, constant: -16),
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor, constant: 8),
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 8)
        ])

        let today = NSButton(checkboxWithTitle: "Include Today tabs (unpinned tabs)", target: nil, action: nil)
        today.state = includeToday ? .on : .off
        today.setAccessibilityIdentifier("bato-arc-import-today")
        ClosureTarget.attach(to: today) { [weak self] in
            self?.includeToday = today.state == .on
            self?.showPreview()
        }
        add(today)
        if !done.isEmpty {
            let again = NSButton(checkboxWithTitle: "Import already imported spaces again as copies", target: nil, action: nil)
            again.state = importAgain ? .on : .off
            again.setAccessibilityIdentifier("bato-arc-import-again")
            ClosureTarget.attach(to: again) { [weak self] in
                guard let self else { return }
                self.importAgain = again.state == .on
                self.included = self.importAgain ? Set(self.staging.spaces.map(\.id)) :
                    self.included.subtracting(self.alreadyImported)
                self.showPreview()
            }
            add(again)
        }

        totals.font = .systemFont(ofSize: 12, weight: .medium)
        totals.setAccessibilityIdentifier("bato-arc-import-totals")
        unsupported.font = .systemFont(ofSize: 11)
        unsupported.textColor = .secondaryLabelColor
        unsupported.setAccessibilityIdentifier("bato-arc-import-unsupported")
        add(totals)
        add(unsupported)
        errorLabel.stringValue = ""
        styleError()
        add(errorLabel)

        let cancel = button("Cancel", id: "bato-arc-import-cancel") { [weak self] in self?.dismiss(.cancel) }
        cancel.keyEquivalent = "\u{1b}"
        let importButton = button("Import", id: "bato-arc-import-apply") { [weak self] in self?.runImport() }
        importButton.keyEquivalent = "\r"
        self.importButton = importButton
        window?.defaultButtonCell = importButton.cell as? NSButtonCell
        add(buttons([cancel, importButton]))
        refreshSummary()
    }

    private func refreshSummary() {
        // Against the real organization, so Profiles from an earlier import of this file are not counted as new.
        let plan = selected.isEmpty ? nil :
            try? ImportPlan.make(staging, options: options(salt: importAgain ? "preview" : ""), into: currentState())
        guard let plan else {
            totals.stringValue = describeTotals(workspaces: "0 workspaces", pins: 0, folders: 0, favorites: 0, tabs: 0)
            unsupported.stringValue = ""
            importButton?.isEnabled = false
            return
        }
        let s = plan.summary
        totals.stringValue = describeTotals(workspaces: s.workspaceDescription(asCopies: importAgain), pins: s.pins,
                                            folders: s.folders, favorites: s.favorites, tabs: s.tabs)
        let notes = s.warningCounts.compactMap { kind, count in Self.describe(kind, count) }.sorted()
        unsupported.stringValue = notes.isEmpty ? "Nothing unsupported." :
            "Not imported or simplified:\n" + notes.map { "• \($0)" }.joined(separator: "\n")
        importButton?.isEnabled = true
    }

    private func describeTotals(workspaces: String, pins: Int, folders: Int, favorites: Int, tabs: Int) -> String {
        "\(workspaces) · " +
            "\(plural(pins, "pin")) · \(plural(folders, "folder")) · \(plural(favorites, "favorite")) · " +
            "\(plural(tabs, "tab"))"
    }

    private func runImport() {
        let plan: ImportPlan
        do { plan = try ImportPlan.make(staging, options: options(salt: salt), into: currentState()) }
        catch let error as ImportPlanError {
            fail(error == .alreadyImported ? "These spaces were already imported. Nothing was changed. " +
                 "Choose “import again as copies” to add them again." : error.localizedDescription)
            return
        } catch { return fail("This Arc data can’t be added to the current organization.") }
        switch apply(plan) {
        case .success(let result):
            applied = result
            showResult(plan.summary)
        case .failure(let failure): fail(failure.message)
        }
    }

    // MARK: Result

    private func showResult(_ summary: ImportSummary) {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        add(label("Import complete", size: 15, weight: .semibold))
        add(label("Added \(summary.workspaceDescription(asCopies: importAgain)): " +
                  "\(plural(summary.pins, "pin")), \(plural(summary.folders, "folder")), " +
                  "\(plural(summary.favorites, "favorite")), \(plural(summary.tabs, "tab")).", secondary: false))
        if summary.profiles > 0 {
            add(label("Each new Profile keeps its own logins and site data in a separate browser window, " +
                      "opened the first time you use one of its workspaces.", secondary: true))
        }
        add(label("Undo restores your organization to exactly how it was before the import. It stays available only " +
                  "until anything else in Bato changes.", secondary: true))
        errorLabel.stringValue = ""
        styleError()
        add(errorLabel)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        add(spacer)
        let undoButton = button("Undo Import", id: "bato-arc-import-undo") { [weak self] in self?.runUndo() }
        let done = button("Done", id: "bato-arc-import-done") { [weak self] in self?.dismiss(.OK) }
        done.keyEquivalent = "\r"
        window?.defaultButtonCell = done.cell as? NSButtonCell
        add(buttons([undoButton, done]))
    }

    private func runUndo() {
        guard let applied else { return }
        switch undo(applied) {
        case .success: dismiss(.cancel)
        case .failure(let failure): fail(failure.message)
        }
    }

    // MARK: Pieces

    private func fail(_ message: String) {
        errorLabel.stringValue = message
        NSAccessibility.post(element: errorLabel, notification: .announcementRequested,
                             userInfo: [.announcement: message])
    }

    private func styleError() {
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityIdentifier("bato-arc-import-error")
    }

    private func add(_ view: NSView) {
        content.addArrangedSubview(view)
        if view is NSTextField || view is NSScrollView || view is NSStackView {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: secondary ? 11 : size, weight: weight)
        if secondary { field.textColor = .secondaryLabelColor }
        return field
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.setAccessibilityIdentifier(id)
        ClosureTarget.attach(to: button, action)
        return button
    }

    private func buttons(_ trailing: [NSButton]) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer] + trailing)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func dismiss(_ response: NSApplication.ModalResponse) {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window, returnCode: response)
        window.orderOut(nil)
    }

    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private func describe(_ space: ImportSummary.Space?) -> String {
        guard let space else { return "" }
        return "\(plural(space.pins, "pin")) · \(plural(space.folders, "folder")) · " +
            "\(plural(space.tabs, "tab")) · \(plural(space.splits, "split"))"
    }

    private static func describe(_ kind: ImportWarning.Kind, _ count: Int) -> String? {
        let n = count
        switch kind {
        case .unsupportedURL: return "\(n) page\(n == 1 ? "" : "s") with addresses Bato can’t open (such as arc: or file:)"
        case .unknownItem: return "\(n) item\(n == 1 ? "" : "s") of unknown type"
        case .liveFolder: return "\(n) live folder\(n == 1 ? "" : "s") (GitHub, Bitbucket) imported without live content"
        case .depthHoisted: return "\(n) folder\(n == 1 ? "" : "s") nested too deeply, moved up"
        case .splitFlattened: return "\(n) split view\(n == 1 ? "" : "s") Bato can’t represent, imported as separate pages"
        case .interleavingLost: return "Pin and folder order mixed in \(n) place\(n == 1 ? "" : "s"), regrouped"
        case .cycle, .duplicateItem, .missingReference, .excessiveNesting:
            return "\(n) damaged or repeated item\(n == 1 ? "" : "s") skipped"
        case .truncatedName, .nameDefaulted: return "\(n) name\(n == 1 ? "" : "s") shortened or replaced"
        case .droppedIcon: return "\(n) space icon\(n == 1 ? "" : "s") (Bato uses one color per space)"
        case .droppedTheme: return "\(n) space theme\(n == 1 ? "" : "s") reduced to one color"
        case .duplicateFavorite: return "\(n) repeated favorite\(n == 1 ? "" : "s") skipped"
        }
    }
}

/// A scroll view's clip view is bottom-origin; a flipped document keeps short content at the top.
@MainActor
private final class TopAlignedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// Retains a closure as the control's target without subclassing it.
@MainActor
private final class ClosureTarget: NSObject {
    private let action: () -> Void
    private init(_ action: @escaping () -> Void) { self.action = action }
    @objc private func fire() { action() }

    static func attach(to control: NSControl, _ action: @escaping () -> Void) {
        let target = ClosureTarget(action)
        control.target = target
        control.action = #selector(fire)
        objc_setAssociatedObject(control, &key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var key: UInt8 = 0
}
