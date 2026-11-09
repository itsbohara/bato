import BatoCore
import BatoPersistence
import CryptoKit
import Foundation

public struct BrowserImportPreview: Equatable, Sendable {
    public var favoritesToAdd: Int
    /// Favorites already in the Profile (same address) or repeated in the source.
    public var favoritesSkipped: Int
    public var bookmarks: Int
    public var historyPages: Int
    /// Spaces the import adds, and those skipped because an earlier import already added them.
    public var spaces: ImportSummary?
    public var spacesAlreadyImported: Int
}

/// What "Bring everything over" would change, validated and ready to apply. Nothing is written until
/// `apply`. Favorites, Spaces, pinned items and folders go through the organization transaction;
/// bookmarks and history are staged for the Profile's Chromium data (see `PendingBrowserData`).
public struct BrowserImportPlan: Sendable {
    public var state: BrowserState
    public var preview: BrowserImportPreview
    public var pending: PendingBrowserData?
    public var targetProfileID: UUID
    public var warnings: [ImportWarning]

    /// - Parameters:
    ///   - targetProfileID: the existing Profile that receives Favorites, bookmarks and history.
    ///   - idSalt: changes every derived identifier so a deliberate second import adds copies.
    public static func make(_ snapshot: BrowserSnapshot, items: Set<ImportItem>, into existing: BrowserState,
                            targetProfileID: UUID, idSalt: String = "") throws -> BrowserImportPlan {
        try existing.validate()
        guard let profileIndex = existing.profiles.firstIndex(where: { $0.id == targetProfileID }) else {
            throw BrowserStateError.missingProfile
        }
        let ids = IdentityFactory(digest: "browser-import|\(snapshot.source.rawValue)|\(snapshot.profileID)", salt: idSalt)
        var state = existing
        var added = 0, skipped = 0

        if items.contains(.favorites) {
            var known = Set(state.profiles[profileIndex].favorites.flatMap { [$0.savedURL, $0.lastURL].compactMap { $0?.duplicateKey } })
            var knownIDs = Set(state.profiles[profileIndex].favorites.map(\.id))
            for page in snapshot.favorites {
                let key = page.url.duplicateKey
                let id = ids.id("favorite", key)
                guard BrowserState.isValidPageURL(page.url), known.insert(key).inserted, knownIDs.insert(id).inserted else {
                    skipped += 1
                    continue
                }
                state.profiles[profileIndex].favorites.append(PageEntry(
                    id: id, title: page.title.isEmpty ? page.url.host ?? page.url.absoluteString : page.title,
                    savedURL: page.url, lastURL: page.url, kind: .favorite))
                added += 1
            }
        }

        var summary: ImportSummary?
        var alreadyImported = 0
        var warnings: [ImportWarning] = []
        if items.contains(.spaces), let staging = snapshot.spaces {
            let done = ImportPlan.alreadyImportedSpaceIDs(staging, in: state, idSalt: idSalt)
            alreadyImported = done.count
            if done.count < staging.spaces.count {
                let plan = try ImportPlan.make(staging, options: ImportOptions(excludedSpaceIDs: done, idSalt: idSalt), into: state)
                state = plan.state
                summary = plan.summary
                warnings = plan.warnings
            }
        }
        try state.validate()

        let bookmarks = items.contains(.bookmarks) ? snapshot.bookmarks : []
        let history = items.contains(.history) ? snapshot.history : []
        let pending = bookmarks.isEmpty && history.isEmpty ? nil : PendingBrowserData(
            batchID: String(ids.id("batch", "pending").uuidString.prefix(8)).lowercased(),
            source: snapshot.source, bookmarks: bookmarks, history: history)
        return BrowserImportPlan(
            state: state,
            preview: BrowserImportPreview(favoritesToAdd: added, favoritesSkipped: skipped,
                                          bookmarks: bookmarks.reduce(0) { $0 + $1.pageCount }, historyPages: history.count,
                                          spaces: summary, spacesAlreadyImported: alreadyImported),
            pending: pending, targetProfileID: targetProfileID, warnings: warnings)
    }

    public struct Applied: Sendable {
        public var organization: ImportTransaction.Applied
        /// Bookmarks and history wait for the Profile's engine to be idle; see `PendingImportStore.applyPending`.
        public var stagedForNextLaunch: Bool
    }

    /// Saves the organization as one transaction with a pre-import snapshot, then stages bookmarks and
    /// history. Staging happens only after the organization save succeeded, so a failed save leaves
    /// nothing behind; re-applying the same plan changes nothing further.
    public func apply(to store: OrganizationStore<BrowserState>, pending pendingStore: PendingImportStore) throws -> Applied {
        let organization = try ImportTransaction.apply(state, to: store)
        if let pending { try pendingStore.stage(pending, profileKey: targetProfileID.uuidString) }
        return Applied(organization: organization, stagedForNextLaunch: pending != nil)
    }
}
