import Foundation
import Darwin
import BatoCore

/// Process-local bookkeeping for one window's transient preview. This does not
/// create, render, close or persist a page; a future host must perform those effects.
/// In particular, requesting dismissal must still go through the engine's normal
/// before-unload confirmation, and promotion must attach the returned live page.
public struct PeekSession: Sendable {
    public struct Preview: Equatable, Sendable {
        fileprivate var revision = UUID()
        public let parent: LivePage
        public let page: LivePage
        public fileprivate(set) var url: URL
        public fileprivate(set) var title: String
        public fileprivate(set) var isPendingDismissal: Bool
    }

    public private(set) var preview: Preview?

    public init() {}

    /// Link interception is restricted to absolute, credential-free HTTP(S).
    /// This is input eligibility, not an origin/security or navigation policy.
    public static func isEligibleLink(_ url: URL) -> Bool {
        guard url.baseURL == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              case .navigate = CommandBarInput.resolve(url.absoluteString),
              let host = components.host, !host.hasPrefix("."), !host.hasSuffix("..") else {
            return false
        }
        // Validate bracketed IP literals explicitly. For ordinary hosts,
        // disallow empty labels and malformed DNS label boundaries as well.
        if host.hasPrefix("[") && host.hasSuffix("]") {
            var address = in6_addr()
            return String(host.dropFirst().dropLast()).withCString { inet_pton(AF_INET6, $0, &address) == 1 }
        }
        let labels = host.hasSuffix(".") ? host.dropLast().split(separator: ".", omittingEmptySubsequences: false)
            : host[...].split(separator: ".", omittingEmptySubsequences: false)
        return !labels.isEmpty && labels.allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 63 && $0.first != "-" && $0.last != "-" &&
            $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        }
    }

    /// The caller supplies a fresh live token only after arranging its engine
    /// context. Matching Profile UUIDs express intent, not proven engine isolation.
    /// An occupied preview is never implicitly replaced (it may have unsaved work).
    @discardableResult
    public mutating func open(parent: LivePage, page: LivePage, url: URL, title: String = "") -> Bool {
        guard preview == nil, Self.isEligibleLink(url), parent.profileID == page.profileID,
              parent.entryID != page.entryID else { return false }
        preview = Preview(parent: parent, page: page, url: url, title: title, isPendingDismissal: false)
        return true
    }

    /// Returns the token to pass to requestClose, once. Keep the preview until
    /// the engine confirms closure; cancellation restores normal interaction.
    public mutating func requestDismissal() -> LivePage? {
        guard var current = preview, !current.isPendingDismissal else { return nil }
        current.isPendingDismissal = true
        current.revision = UUID()
        preview = current
        return current.page
    }

    /// Snapshot for the host's adoption/save attempt. Preparing leaves the live
    /// preview owned here, so a failed attempt needs no rollback in this session.
    public func preparePromotion() -> Preview? {
        guard let current = preview, !current.isPendingDismissal else { return nil }
        return current
    }

    /// Finish only after the host successfully adopts this exact snapshot. The
    /// host must revalidate before committing if callbacks can reenter its work.
    /// Navigation, dismissal or replacement makes an old preparation stale.
    /// No engine close/recreation or organization save occurs here.
    @discardableResult
    public mutating func completePromotion(_ prepared: Preview) -> Bool {
        guard let current = preview, !current.isPendingDismissal, current == prepared else { return false }
        preview = nil
        return true
    }

    /// Releases the preview after the engine has ended its presentation; unlike
    /// promotion, the host still owns closing the page.
    @discardableResult
    public mutating func finish() -> Preview? {
        defer { preview = nil }
        return preview
    }

    /// Consume only exact live-generation callbacks. Navigation after opening is
    /// engine-authoritative and is not restricted by link interception eligibility.
    @discardableResult
    public mutating func handle(_ event: PageEvent) -> Bool {
        guard var current = preview else { return false }
        switch event {
        case let .navigation(page, url, title) where page == current.page:
            current.revision = UUID()
            current.url = url
            current.title = title
            preview = current
        case let .closeCancelled(page) where page == current.page && current.isPendingDismissal:
            current.revision = UUID()
            current.isPendingDismissal = false
            preview = current
        case let .closed(page), let .creationFailed(page), let .unloaded(page):
            guard page == current.page else { return false }
            preview = nil
        default:
            return false
        }
        return true
    }
}
