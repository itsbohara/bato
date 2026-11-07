import AppKit
import BatoBlocking

/// "Blocking: On/Off for this site" plus the blocked count for the active page, as menu items.
///
/// The host watches `blocking-settings.json`, so a change reaches the request filter within a
/// polling tick; `reload` therefore runs after `reloadDelay` rather than immediately.
@MainActor
public final class BlockingControls: NSObject, NSMenuItemValidation {
    public struct ActivePage {
        public let url: URL
        public let browserID: Int32

        public init(url: URL, browserID: Int32) {
            self.url = url
            self.browserID = browserID
        }
    }

    private enum Tag: Int {
        case toggle = 1
        case count
    }

    private let service: BlockingService
    private let activePage: () -> ActivePage?
    private let reload: (Int32) -> Void
    private let reloadDelay: TimeInterval

    public init(service: BlockingService, activePage: @escaping () -> ActivePage?,
                reload: @escaping (Int32) -> Void, reloadDelay: TimeInterval = 0.5) {
        self.service = service
        self.activePage = activePage
        self.reload = reload
        self.reloadDelay = reloadDelay
    }

    public func menuItems() -> [NSMenuItem] {
        let toggle = NSMenuItem(title: "Blocking", action: #selector(toggleForSite), keyEquivalent: "")
        toggle.target = self
        toggle.tag = Tag.toggle.rawValue
        let count = NSMenuItem(title: "", action: #selector(toggleForSite), keyEquivalent: "")
        count.target = self
        count.tag = Tag.count.rawValue
        return [toggle, count]
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let page = activePage()
        switch Tag(rawValue: item.tag) {
        case .toggle:
            let enabled = service.settings.enabled
            let blocking = page.map { service.isBlocking(pageURL: $0.url) } ?? enabled
            item.title = enabled ? "Blocking: \(blocking ? "On" : "Off") for this site" : "Blocking: Off for all sites"
            item.state = blocking ? .on : .off
            return enabled && page.flatMap { BlockingSettings.host(of: $0.url) } != nil
        case .count:
            let count = page.map { service.counters.count(for: $0.browserID) } ?? 0
            item.title = "\(count) blocked on this page"
            return false
        case nil:
            return false
        }
    }

    @objc private func toggleForSite() {
        guard let page = activePage() else { return }
        let blocking = service.isBlocking(pageURL: page.url)
        guard (try? service.setBlocking(!blocking, forPageURL: page.url)) != nil else { return }
        let reload = reload
        DispatchQueue.main.asyncAfter(deadline: .now() + reloadDelay) { reload(page.browserID) }
    }
}
