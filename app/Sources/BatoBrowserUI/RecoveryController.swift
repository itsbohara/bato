import AppKit
import BatoBlocking
import BatoCore
import BatoPersistence

/// Launch recovery and backups for the workspace: abnormal-termination detection, the recovery offer,
/// rolling backups and restore. Organization and per-Profile blocking settings are covered; engine data is not.
@MainActor
final class RecoveryController {
    static let confirmationDelay: TimeInterval = 10

    private let directory: URL
    private let store: OrganizationStore<BrowserState>
    private let backups: BackupStore
    private let coordinator: RecoveryCoordinator
    private(set) var launchStatus: LaunchStatus = .clean
    /// Set when a restore staged from Settings could not be applied at launch.
    private(set) var startupNotice: String?

    init(directory: URL, store: OrganizationStore<BrowserState>) {
        self.directory = directory
        self.store = store
        backups = BackupStore(directory: directory)
        coordinator = RecoveryCoordinator(directory: directory, backups: backups)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForQuit() }
        }
    }

    /// Call before the organization is read, so a crash while loading is detected next launch.
    func beginLaunch() { launchStatus = coordinator.beginLaunch() }

    /// Applies a restore staged from Settings. Call right after `store.load` and before blocking reads its files.
    func applyPendingRestore() -> BrowserState? {
        guard let id = backups.takePendingRestore() else { return nil }
        do {
            let result = try backups.restore(id, into: store)
            BlockingHost.shared.profiles?.reloadSettings()
            if !result.failedFiles.isEmpty {
                startupNotice = "Organization was restored, but \(result.failedFiles.count) blocking settings file(s) could not be."
            }
            return result.state
        } catch {
            startupNotice = "The backup could not be restored: \(Self.reason(error)) Your current organization was not changed."
            return nil
        }
    }

    func prepareForQuit() { coordinator.endCleanly() }

    /// Records the organization this session starts with. Call once the launch offer is resolved and before
    /// pages open; it becomes the recovery snapshot only after the launch is confirmed.
    func captureSessionStart() {
        guard let organization = try? store.committedDocument() else { return }
        if let error = coordinator.captureSessionStart(organization: organization, files: settingsFiles()) { report(error) }
    }

    /// Title of the restore waiting for the next launch, for Settings.
    var stagedRestoreTitle: String? { backups.stagedRestore().map(Self.title) }

    func cancelStagedRestore() { backups.cancelStagedRestore() }

    /// Marks the launch successful after `confirmationDelay` and refreshes the recovery snapshot and daily backup.
    func confirmLaunchSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationDelay) { [weak self] in
            MainActor.assumeIsolated { self?.confirmLaunch() }
        }
    }

    private func confirmLaunch() {
        let organization = try? store.committedDocument()
        if let error = coordinator.confirmLaunch(organization: organization, files: settingsFiles()) { report(error) }
    }

    private func report(_ error: BackupError) {
        NSLog("Bato: backup could not be written (%@)", String(describing: error))
    }

    // MARK: Launch offer

    /// Offers last-session recovery. `canAdopt` and `adopt` hand a restored organization to the runtime, which must
    /// not have a live page yet; `completion` runs once the sheet is resolved, whatever the choice.
    func presentLaunchOffer(on window: NSWindow, canAdopt: @escaping () -> Bool,
                            adopt: @escaping (BrowserState) -> Bool, completion: @escaping () -> Void) {
        guard case .abnormal(let crash) = launchStatus else { return completion() }
        let snapshot = backups.list().first { $0.kind == .lastSession }
        var text = "Your sidebar was saved after your last change, so nothing is lost."
        if crash.isRepeating {
            text += " This has now happened \(crash.consecutiveFailures) times in a row; a page that opens at launch may be the cause."
        }
        if let snapshot {
            text += " You can also go back to how it was when your last full session began, \(Self.format(snapshot.createdAt))."
        }
        var buttons = [RecoverySheet.Button(title: "Keep Current", isDefault: true)]
        if snapshot != nil { buttons.append(.init(title: "Restore Session", isDefault: false)) }
        RecoverySheet.present(on: window, symbol: "arrow.counterclockwise.circle", title: "Bato didn’t quit properly last time",
                              body: text, buttons: buttons, cancelIndex: 0) { [weak self] choice in
            guard let self else { return }
            if snapshot != nil, choice == 1 {
                self.restoreSessionStart(on: window, canAdopt: canAdopt, adopt: adopt, completion: completion)
            } else {
                completion()
            }
        }
    }

    private func restoreSessionStart(on window: NSWindow, canAdopt: () -> Bool, adopt: (BrowserState) -> Bool,
                                     completion: @escaping () -> Void) {
        guard canAdopt() else {
            return showFailure("A page is already open, so the session can’t be swapped now. Use Settings, Advanced, Restore from backup.",
                               on: window, completion: completion)
        }
        do {
            let result = try backups.restore(BackupStore.lastSessionID, into: store)
            BlockingHost.shared.profiles?.reloadSettings()
            if adopt(result.state) { completion() }
            else { showFailure("The session was restored on disk. Quit and reopen Bato to use it.", on: window, completion: completion) }
        } catch {
            showFailure("The session couldn’t be restored: \(Self.reason(error)) Your current organization was not changed.",
                        on: window, completion: completion)
        }
    }

    // MARK: Restore from Settings

    /// Lets the user pick a backup and stages it for the next launch: live pages are bound to the current
    /// organization, so it is replaced before anything is loaded. `didChange` runs when a restore is staged.
    func presentRestorePicker(on window: NSWindow, didChange: @escaping () -> Void = {}) {
        let available = backups.list()
        guard !available.isEmpty else {
            return showFailure("There are no backups yet. Bato keeps one daily copy and refreshes it while you use the browser.",
                               on: window, completion: {})
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: RecoverySheet.contentWidth, height: 26))
        picker.addItems(withTitles: available.map(Self.title))
        picker.setAccessibilityIdentifier("bato-restore-backup-picker")
        RecoverySheet.present(
            on: window, symbol: "clock.arrow.circlepath", title: "Restore from backup",
            body: "Backups cover your sidebar organization and blocking settings, not passwords, cookies or open pages. The restore happens the next time Bato opens, and what you have now is kept as “Before last restore”.",
            accessory: picker,
            buttons: [.init(title: "Cancel", isDefault: false), .init(title: "Restore on Relaunch", isDefault: true)],
            cancelIndex: 0) { [weak self] choice in
            guard let self, choice == 1 else { return }
            self.stage(available[picker.indexOfSelectedItem], on: window, didChange: didChange)
        }
    }

    private func stage(_ backup: BackupInfo, on window: NSWindow, didChange: @escaping () -> Void) {
        do { try backups.stageRestore(backup.id) }
        catch { return showFailure("The restore couldn’t be scheduled: \(Self.reason(error))", on: window, completion: {}) }
        didChange()
        RecoverySheet.present(on: window, symbol: "arrow.triangle.2.circlepath", title: "Quit Bato to finish restoring",
                              body: "“\(Self.title(backup))” will replace your organization the next time Bato opens.",
                              buttons: [.init(title: "Later", isDefault: false), .init(title: "Quit Bato", isDefault: true)],
                              cancelIndex: 0) { choice in
            if choice == 1 { NSApp.terminate(nil) }
        }
    }

    func showNoticeIfNeeded(on window: NSWindow) {
        guard let notice = startupNotice else { return }
        startupNotice = nil
        showFailure(notice, on: window, completion: {})
    }

    // MARK: Pieces

    private func showFailure(_ text: String, on window: NSWindow, completion: @escaping () -> Void) {
        RecoverySheet.present(on: window, symbol: "exclamationmark.triangle", title: "Backup problem", body: text,
                              buttons: [.init(title: "OK", isDefault: true)], cancelIndex: 0) { _ in completion() }
    }

    /// Blocking settings only: a Profile's other blocking files (lists, counters) are rebuilt by the host.
    private func settingsFiles() -> [String: Data] {
        let root = BlockingProfiles.rootDirectory(stateDirectory: directory)
        var files: [String: Data] = [:]
        for key in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] where BlockingProfiles.isValidKey(key) {
            let name = BlockingSettingsStore.fileName
            if let bytes = try? Data(contentsOf: root.appendingPathComponent(key).appendingPathComponent(name)) {
                files["blocking/\(key)/\(name)"] = bytes
            }
        }
        return files
    }

    private static func title(_ backup: BackupInfo) -> String {
        let when = format(backup.createdAt)
        switch backup.kind {
        case .daily: return "Daily backup, \(when)"
        case .lastSession: return "Start of last session, \(when)"
        case .preImport: return "Before last import, \(when)"
        case .preMigration: return "Before last upgrade, \(when)"
        case .preRestore: return "Before last restore, \(when)"
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Shown in place of the sidebar when organization can't be opened. The file is never modified.
    nonisolated static func unavailableMessage(for error: Error) -> String {
        let reason = (error as? LocalizedError)?.errorDescription ?? "The organization file could not be opened."
        return "\(reason) Nothing was changed. Quit Bato, then copy a file from the backups folder next to organization.json over it, or ask for help with the version of Bato you use."
    }

    private static func reason(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "An unexpected error occurred."
    }
}

/// A compact card sheet for recovery and restore: optional icon, title, body, optional accessory and
/// side-by-side buttons, about 320 pt wide.
@MainActor
final class RecoverySheet: NSObject {
    struct Button {
        let title: String
        let isDefault: Bool
    }

    static let cardWidth: CGFloat = 320
    static let inset: CGFloat = 16
    static let contentWidth = cardWidth - inset * 2

    private let panel: SheetPanel
    private let completion: (Int) -> Void
    private weak var parent: NSWindow?

    static func present(on parent: NSWindow, symbol: String?, title: String, body: String, accessory: NSView? = nil,
                        buttons: [Button], cancelIndex: Int, completion: @escaping (Int) -> Void) {
        let sheet = RecoverySheet(parent: parent, symbol: symbol, title: title, body: body, accessory: accessory,
                                  buttons: buttons, cancelIndex: cancelIndex, completion: completion)
        parent.beginSheet(sheet.panel) { _ in _ = sheet }
    }

    private init(parent: NSWindow, symbol: String?, title: String, body: String, accessory: NSView?,
                 buttons: [Button], cancelIndex: Int, completion: @escaping (Int) -> Void) {
        self.parent = parent
        self.completion = completion
        panel = SheetPanel(contentRect: NSRect(x: 0, y: 0, width: Self.cardWidth, height: 200),
                           styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.cancelIndex = cancelIndex
        panel.onCancel = { [weak self] index in self?.finish(index) }

        var views: [NSView] = []
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let icon = NSImageView(image: image)
            icon.symbolConfiguration = .init(pointSize: 26, weight: .regular)
            icon.contentTintColor = .secondaryLabelColor
            views.append(icon)
        }
        let heading = NSTextField(wrappingLabelWithString: title)
        heading.font = .systemFont(ofSize: 15, weight: .bold)
        heading.preferredMaxLayoutWidth = Self.contentWidth
        heading.setAccessibilityIdentifier("bato-recovery-title")
        let message = NSTextField(wrappingLabelWithString: body)
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = Self.contentWidth
        message.setAccessibilityIdentifier("bato-recovery-body")
        views += [heading, message]
        if let accessory { views.append(accessory) }

        let row = NSStackView(views: buttons.enumerated().map { index, spec in
            let button = NSButton(title: spec.title, target: self, action: #selector(buttonPressed(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.setAccessibilityIdentifier("bato-recovery-button-\(index)")
            if spec.isDefault { button.keyEquivalent = "\r" }
            return button
        })
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        views.append(row)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        if let last = views.dropLast().last { stack.setCustomSpacing(16, after: last) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.inset),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.inset),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.inset),
                row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ])
            if let accessory { accessory.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        }
        SidebarStyle.fitSheet(panel, to: stack, horizontalInset: Self.inset, verticalInset: Self.inset)
        panel.defaultButtonCell = row.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.keyEquivalent == "\r" }?.cell as? NSButtonCell
    }

    @objc private func buttonPressed(_ sender: NSButton) { finish(sender.tag) }

    private func finish(_ index: Int) {
        parent?.endSheet(panel)
        completion(index)
    }
}

private final class SheetPanel: NSWindow {
    var cancelIndex = 0
    var onCancel: ((Int) -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?(cancelIndex) }
}
