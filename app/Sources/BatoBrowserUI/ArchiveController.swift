import AppKit
import BatoCore
import BatoRuntime

/// Archives idle tabs on a timer and presents the Archive list for one window's runtime.
@MainActor
final class ArchiveController {
    static let sweepInterval: TimeInterval = 5 * 60

    private let runtime: PageRuntime
    private let window: () -> NSWindow?
    private let canPresent: () -> Bool
    private let restored: () -> Void
    private var sheet: ArchiveSheet?
    private var timer: Timer?

    /// `restored` runs after the sheet closed and a tab was restored, so page work can follow.
    init(runtime: PageRuntime, window: @escaping () -> NSWindow?, canPresent: @escaping () -> Bool,
         restored: @escaping () -> Void) {
        self.runtime = runtime
        self.window = window
        self.canPresent = canPresent
        self.restored = restored
    }

    func start() {
        guard timer == nil else { return }
        _ = runtime.archiveIdleTabs()
        timer = Timer.scheduledTimer(withTimeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.runtime.archiveIdleTabs() }
        }
    }

    func show() {
        guard sheet == nil, canPresent(), let parent = window() else { return }
        let runtime = runtime
        let archive = ArchiveSheet(
            records: { query in
                runtime.state.archive.records(inProfile: runtime.state.currentWorkspace.profileID, matching: query)
            },
            workspaceName: { id in runtime.state.workspaces.first { $0.id == id }?.name },
            restore: { id in
                runtime.restoreArchivedTab(id, deferPageSelection: true) ? nil : Self.message(for: runtime.lastError)
            },
            delete: { id in runtime.deleteArchivedTab(id) ? nil : Self.message(for: runtime.lastError) },
            now: { runtime.clock() })
        sheet = archive
        guard let panel = archive.window else { sheet = nil; return }
        parent.beginSheet(panel) { [weak self, weak parent] response in
            guard let self else { return }
            self.sheet = nil
            guard response == .OK else { return }
            // Engine page work must not start inside the sheet's completion.
            DispatchQueue.main.async { [weak self, weak parent] in
                guard let self, let parent, self.window() === parent else { return }
                self.restored()
            }
        }
        archive.focusSearch()
    }

    private static func message(for error: PageRuntimeError?) -> String {
        error == .saveFailed
            ? "Changes couldn’t be saved. Reopen Bato to reload organization."
            : "That tab is no longer in the archive."
    }
}
