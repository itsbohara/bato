import Foundation

/// The process-wide service the browser host talks to.
public final class BlockingHost: @unchecked Sendable {
    public static let shared = BlockingHost()

    private let lock = NSLock()
    private var current: BlockingService?

    public var service: BlockingService? { lock.withLock { current } }

    func install(_ service: BlockingService) {
        lock.withLock { current = service }
    }
}

// Optional hooks the browser host resolves with dlsym; absent hooks leave blocking silent.

/// Starts list updates for the blocking directory the host is filtering from. Returns 1 on success.
@_cdecl("BatoSwiftBlockingStart")
public func batoSwiftBlockingStart(_ directory: UnsafePointer<CChar>?) -> Int32 {
    guard let directory else { return 0 }
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    guard url.path.hasPrefix("/") else { return 0 }
    let service = BlockingService(directory: url)
    BlockingHost.shared.install(service)
    service.startPeriodicUpdates()
    return 1
}

/// A top-level navigation began in this browser.
@_cdecl("BatoSwiftBlockingPageStarted")
public func batoSwiftBlockingPageStarted(_ browserID: Int32) {
    BlockingHost.shared.service?.counters.pageStarted(browserID)
}

/// One request was blocked for this browser.
@_cdecl("BatoSwiftBlockingRequestBlocked")
public func batoSwiftBlockingRequestBlocked(_ browserID: Int32) {
    BlockingHost.shared.service?.counters.recordBlocked(browserID)
}
