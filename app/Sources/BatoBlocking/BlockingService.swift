import Foundation

/// One Profile's blocking state: settings, per-page counts and list updates.
public final class BlockingService: @unchecked Sendable {
    public static let defaultUpdateInterval: TimeInterval = 24 * 60 * 60

    public let directory: URL
    public let counters = BlockedCounters()
    private let store: BlockingSettingsStore
    private let updater: FilterListUpdater
    private let lock = NSLock()
    private var updateTask: Task<Void, Never>?

    public init(directory: URL, sources: [FilterListSource] = FilterListSource.defaults,
                fetcher: FilterListFetching = URLSessionListFetcher()) {
        self.directory = directory
        store = BlockingSettingsStore(directory: directory)
        updater = FilterListUpdater(directory: directory, sources: sources, fetcher: fetcher)
    }

    /// `<state>/blocking/<profileKey>`. The engine has one bound Profile today, keyed `default`.
    public static func directory(stateDirectory: URL, profileKey: String = "default") -> URL {
        stateDirectory.appendingPathComponent("blocking").appendingPathComponent(profileKey)
    }

    public var settings: BlockingSettings { store.current() }
    public var exceptions: [String] { settings.exceptions }
    public var settingsRecoveredFromCorruption: Bool { store.recoveredFromCorruption }
    public var listStatus: [String: ListStatus] { get async { await updater.status() } }

    public func isBlocking(pageURL: URL) -> Bool {
        guard let host = BlockingSettings.host(of: pageURL) else { return settings.enabled }
        return settings.blocks(pageHost: host)
    }

    /// Off adds the page's host as an exception. On removes every exception covering it,
    /// including a parent domain's, so the toggle always ends in the state it names.
    public func setBlocking(_ blocking: Bool, forPageURL url: URL) throws {
        guard let host = BlockingSettings.host(of: url) else { throw BlockingSettingsError.invalidHost }
        try store.update { settings in
            if blocking {
                while let covering = settings.exception(covering: host) { settings.removeException(covering) }
            } else if settings.exception(covering: host) == nil {
                try settings.addException(host)
            }
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        try store.update { $0.enabled = enabled }
    }

    public func removeException(host: String) throws {
        try store.update { $0.removeException(host) }
    }

    /// Checks lists now and then every `interval`; lists checked more recently are skipped.
    public func startPeriodicUpdates(interval: TimeInterval = defaultUpdateInterval) {
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
