import Foundation

/// Blocked-request counts per page (CEF browser identifier). The host calls in from the
/// network thread; a page's count restarts when a new top-level navigation begins.
public final class BlockedCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int32: Int] = [:]
    private var observer: (@Sendable (Int32, Int) -> Void)?

    public init() {}

    /// Called after each change, outside the lock and possibly off the main thread.
    public func setObserver(_ observer: (@Sendable (Int32, Int) -> Void)?) {
        lock.withLock { self.observer = observer }
    }

    public func count(for browserID: Int32) -> Int {
        lock.withLock { counts[browserID] ?? 0 }
    }

    public func pageStarted(_ browserID: Int32) {
        change(browserID) { _ in 0 }
    }

    public func recordBlocked(_ browserID: Int32) {
        change(browserID) { ($0 ?? 0) + 1 }
    }

    public func forget(_ browserID: Int32) {
        lock.withLock { counts[browserID] = nil }
    }

    private func change(_ browserID: Int32, _ next: (Int?) -> Int) {
        guard browserID > 0 else { return }
        let (value, observer) = lock.withLock {
            let value = next(counts[browserID])
            counts[browserID] = value
            return (value, self.observer)
        }
        observer?(browserID, value)
    }
}
