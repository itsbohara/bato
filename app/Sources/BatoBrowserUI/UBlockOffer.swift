import AppKit
import BatoBlocking

/// The optional uBlock Origin filter lists: a one-time first-run offer, and the same offer from
/// Settings > Privacy. Nothing is downloaded until the user chooses Add Lists.
@MainActor
enum UBlockOffer {
    static let licenseNote = "The lists are published by the uBlock Origin project under GPL-3.0. Bato downloads them from ublockorigin.github.io, keeps them up to date, and works with its built-in blocking. They add no extension."

    private static var activeBlocking: BlockingProfiles? { BlockingHost.shared.profiles }

    /// Shows the first-run offer once. Dismissing it, by any button or Escape, counts as an answer.
    static func offerIfDue(on window: NSWindow) {
        guard let blocking = activeBlocking, blocking.shouldOfferUBlockLists, window.attachedSheet == nil else { return }
        present(on: window, blocking: blocking, changed: {})
    }

    /// Asks again whatever was answered before. `changed` runs once the answer was applied.
    static func present(on window: NSWindow, blocking: BlockingProfiles, changed: @escaping () -> Void) {
        RecoverySheet.present(
            on: window, symbol: "shield.lefthalf.filled", title: "Add uBlock Origin filter lists?",
            body: "Block more ads, trackers and malicious sites with the filter lists from uBlock Origin. Nothing is downloaded unless you add them.\n\n\(licenseNote)",
            buttons: [.init(title: "Not Now", isDefault: false), .init(title: "Add Lists", isDefault: true)],
            cancelIndex: 0) { index in
            guard index == 1 else {
                try? blocking.declineUBlockLists()
                return changed()
            }
            Task { @MainActor in
                let outcomes = try? await blocking.enableUBlockLists()
                changed()
                report(outcomes, on: window)
            }
        }
    }

    static func remove(blocking: BlockingProfiles, changed: @escaping () -> Void) {
        Task { @MainActor in
            try? await blocking.disableUBlockLists()
            changed()
        }
    }

    private static func report(_ outcomes: [String: ListUpdateOutcome]?, on window: NSWindow) {
        guard window.isVisible else { return }
        let failed = outcomes?.values.contains { outcome in
            switch outcome {
            case .updated, .unchanged: false
            case .rejected, .failed: true
            }
        } ?? true
        let title = failed ? "Some lists couldn’t be downloaded" : "uBlock Origin lists added"
        let body = failed
            ? "Bato will try again with the next daily update. You can also remove them in Settings > Privacy."
            : "They apply to every Profile and update daily."
        guard window.attachedSheet == nil else { return }
        RecoverySheet.present(on: window, symbol: failed ? "exclamationmark.triangle" : "checkmark.shield", title: title,
                              body: body, buttons: [.init(title: "OK", isDefault: true)], cancelIndex: 0) { _ in }
    }
}
