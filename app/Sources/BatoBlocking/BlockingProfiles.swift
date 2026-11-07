import Foundation

/// Blocking for every Profile of one browser process.
///
/// Filter lists are the same for every Profile, so one updater keeps one copy in
/// `<root>/lists` and the host builds one engine from it. Settings and exceptions are
/// per Profile in `<root>/<profileKey>`. Blocked counts are keyed by browser, and browser
/// identifiers are process-wide, so one counters object serves all Profiles.
public final class BlockingProfiles: @unchecked Sendable {
    public let rootDirectory: URL
    public let counters = BlockedCounters()
    private let updater: FilterListUpdater
    private let baseSources: [FilterListSource]
    private let choiceStore: UBlockListsChoiceStore
    private let lock = NSLock()
    private var services: [String: BlockingService] = [:]
    private var updateTask: Task<Void, Never>?

    public init(rootDirectory: URL, sources: [FilterListSource] = FilterListSource.defaults,
                fetcher: FilterListFetching = URLSessionListFetcher()) {
        self.rootDirectory = rootDirectory
        baseSources = sources
        choiceStore = UBlockListsChoiceStore(directory: rootDirectory)
        let wanted = choiceStore.choice == .enabled ? sources + FilterListSource.uBlockOrigin : sources
        updater = FilterListUpdater(directory: rootDirectory, sources: wanted, fetcher: fetcher)
    }

    public var uBlockChoice: UBlockListsChoice { choiceStore.choice }

    /// True until the user has answered the first-run offer.
    public var shouldOfferUBlockLists: Bool { choiceStore.choice == .undecided }

    /// Records a "not now" so the offer is not shown again. Settings can still add the lists.
    public func declineUBlockLists() throws {
        guard choiceStore.choice == .undecided else { return }
        try choiceStore.set(.declined)
    }

    /// The user's consent to download the uBlock Origin lists. Nothing is fetched before this call.
    /// Returns each uBlock list's outcome; a failed list is retried by the daily update.
    @discardableResult
    public func enableUBlockLists() async throws -> [String: ListUpdateOutcome] {
        try choiceStore.set(.enabled)
        await updater.setSources(baseSources + FilterListSource.uBlockOrigin)
        let outcomes = await updater.update(maxAge: BlockingService.defaultUpdateInterval)
        let ids = Set(FilterListSource.uBlockOrigin.map(\.id))
        return outcomes.filter { ids.contains($0.key) }
    }

    /// Stops using the uBlock Origin lists and deletes their downloads.
    public func disableUBlockLists() async throws {
        try choiceStore.set(.declined)
        await updater.setSources(baseSources)
        await updater.discard(FilterListSource.uBlockOrigin)
    }

    /// `<state>/blocking`.
    public static func rootDirectory(stateDirectory: URL) -> URL {
        stateDirectory.appendingPathComponent("blocking")
    }

    /// Keys become directory names, so they are limited to the characters of a UUID or name,
    /// and `lists` is the shared lists directory.
    public static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 64 && key != "lists"
            && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public func service(forProfile key: String) -> BlockingService? {
        guard Self.isValidKey(key) else { return nil }
        return lock.withLock {
            if let existing = services[key] { return existing }
            let service = BlockingService(directory: rootDirectory.appendingPathComponent(key),
                                          updater: updater, counters: counters)
            services[key] = service
            return service
        }
    }

    /// Forgets a deleted Profile's blocking settings and removes their directory.
    public func removeProfile(_ key: String) {
        guard Self.isValidKey(key) else { return }
        lock.withLock { _ = services.removeValue(forKey: key) }
        try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent(key))
    }

    /// Re-reads every Profile's settings file after a backup restore replaced them.
    public func reloadSettings() {
        for service in lock.withLock({ Array(services.values) }) { service.reloadSettings() }
    }

    public var listStatus: [String: ListStatus] { get async { await updater.status() } }

    /// Checks lists now and then every `interval`; lists checked more recently are skipped.
    public func startPeriodicUpdates(interval: TimeInterval = BlockingService.defaultUpdateInterval) {
        lock.withLock {
            updateTask?.cancel()
            let updater = updater
            updateTask = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    await updater.update(maxAge: interval)
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
        }
    }

    public func stopUpdates() {
        lock.withLock {
            updateTask?.cancel()
            updateTask = nil
        }
    }

    @discardableResult
    public func updateListsNow() async -> [String: ListUpdateOutcome] {
        await updater.update()
    }
}
