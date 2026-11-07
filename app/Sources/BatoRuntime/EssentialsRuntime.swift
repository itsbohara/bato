import BatoCore
import Foundation

extension PageRuntime {
    /// Selects the essential's tab in the current Workspace, or opens it there. The Workspace's
    /// Profile decides which Chromium profile serves the page, so history and downloads
    /// never cross Profiles.
    @discardableResult
    public func openEssential(_ essential: BrowserEssential) -> Bool {
        if let existing = state.openEssentialEntry(essential) { return selectEntry(existing.id) }
        return addTab(url: essential.url, title: essential.title)
    }

    /// Opens Chromium's site settings for the page, in a tab of the current Workspace. A repeat for
    /// the same site returns to that tab.
    @discardableResult
    public func openSiteSettings(for page: URL?) -> Bool {
        let url = BrowserEssential.siteSettingsURL(for: page)
        if let existing = state.visibleEntries.first(where: { $0.lastURL == url }) { return selectEntry(existing.id) }
        return addTab(url: url, title: BrowserEssential.sitePermissions.title)
    }
}
