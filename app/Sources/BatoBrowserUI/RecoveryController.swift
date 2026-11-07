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
        let alert = NSAlert()
        alert.messageText = "Bato didn’t quit properly last time"
        var text = "Your sidebar was saved after your last change, so nothing is lost."
        if crash.isRepeating {
            text += " This has now happened \(crash.consecutiveFailures) times in a row; a page that opens at launch may be the cause."
        }
        if let snapshot {
            text += " You can also go back to how it was when that session started, \(Self.format(snapshot.createdAt))."
        }
        alert.informativeText = text
        alert.addButton(withTitle: "Keep Current")
        if snapshot != nil { alert.addButton(withTitle: "Restore Session Start") }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if snapshot != nil, response == .alertSecondButtonReturn {
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
    /// organization, so it is replaced before anything is loaded.
    func presentRestorePicker(on window: NSWindow) {
        let available = backups.list()
        guard !available.isEmpty else {
            return showFailure("There are no backups yet. Bato keeps one daily copy and refreshes it while you use the browser.",
                               on: window, completion: {})
        }
        let alert = NSAlert()
        alert.messageText = "Restore from backup"
        alert.informativeText = "Backups cover your sidebar organization and blocking settings, not passwords, cookies or open pages. The restore happens the next time Bato opens, and what you have now is kept as “Before last restore”."
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        picker.addItems(withTitles: available.map(Self.title))
        picker.setAccessibilityIdentifier("bato-restore-backup-picker")
        alert.accessoryView = picker
        alert.addButton(withTitle: "Restore on Next Launch")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.stage(available[picker.indexOfSelectedItem], on: window)
        }
    }

    private func stage(_ backup: BackupInfo, on window: NSWindow) {
        do { try backups.stageRestore(backup.id) }
        catch { return showFailure("The restore couldn’t be scheduled: \(Self.reason(error))", on: window, completion: {}) }
        let alert = NSAlert()
        alert.messageText = "Quit Bato to finish restoring"
        alert.informativeText = "“\(Self.title(backup))” will replace your organization the next time Bato opens."
        alert.addButton(withTitle: "Quit Bato")
        alert.addButton(withTitle: "Later")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSApp.terminate(nil) }
        }
    }

    func showNoticeIfNeeded(on window: NSWindow) {
        guard let notice = startupNotice else { return }
        startupNotice = nil
        showFailure(notice, on: window, completion: {})
    }

    // MARK: Pieces

    private func showFailure(_ text: String, on window: NSWindow, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Backup problem"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completion() }
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
