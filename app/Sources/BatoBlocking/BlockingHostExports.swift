import Foundation

/// The process-wide registry the browser host talks to.
public final class BlockingHost: @unchecked Sendable {
    public static let shared = BlockingHost()

    private let lock = NSLock()
    private var current: BlockingProfiles?

    public var profiles: BlockingProfiles? { lock.withLock { current } }

    /// The blocking state of the Profile with this key (its Profile UUID string).
    public func service(forProfile key: String) -> BlockingService? { profiles?.service(forProfile: key) }

    func install(_ profiles: BlockingProfiles) {
        lock.withLock { current = profiles }
    }
}

// Optional hooks the browser host resolves with dlsym; absent hooks leave blocking silent.

/// Starts list updates for the blocking root directory the host is filtering from
/// (`<state>/blocking`: shared `lists/` plus one settings directory per Profile). Returns 1 on success.
@_cdecl("BatoSwiftBlockingStart")
public func batoSwiftBlockingStart(_ directory: UnsafePointer<CChar>?) -> Int32 {
    guard let directory else { return 0 }
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    guard url.path.hasPrefix("/") else { return 0 }
    let profiles = BlockingProfiles(rootDirectory: url)
    BlockingHost.shared.install(profiles)
    profiles.startPeriodicUpdates()
    return 1
}

/// A top-level navigation began in this browser.
@_cdecl("BatoSwiftBlockingPageStarted")
public func batoSwiftBlockingPageStarted(_ browserID: Int32) {
    BlockingHost.shared.profiles?.counters.pageStarted(browserID)
}

/// One request was blocked for this browser.
@_cdecl("BatoSwiftBlockingRequestBlocked")
public func batoSwiftBlockingRequestBlocked(_ browserID: Int32) {
    BlockingHost.shared.profiles?.counters.recordBlocked(browserID)
}
