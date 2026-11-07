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
}
