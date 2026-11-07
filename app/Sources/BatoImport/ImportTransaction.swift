import BatoCore
import BatoPersistence
import Foundation

/// Applies a plan as one atomic organization save, with the previous document kept as the
/// pre-import snapshot. Build the plan from the latest organization right before applying.
public enum ImportTransaction {
    public static let snapshotName = "pre-import"

    public struct Applied: Sendable {
        public let state: BrowserState
        public let snapshot: OrganizationStore<BrowserState>.Snapshot
    }

    /// A failure leaves the committed document byte-identical and the store unchanged.
    public static func apply(_ plan: ImportPlan, to store: OrganizationStore<BrowserState>) throws -> Applied {
        let snapshot = try store.saveWithSnapshot(plan.state, named: snapshotName)
        return Applied(state: plan.state, snapshot: snapshot)
    }

    /// Undo is available only while nothing else has been saved since the import: restoring over
    /// later changes would silently discard them. Otherwise it throws `snapshotStale`.
    public static func undo(_ applied: Applied, in store: OrganizationStore<BrowserState>) throws -> BrowserState {
        try store.restore(applied.snapshot)
    }
}
