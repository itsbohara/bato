import AppKit
import BatoCore

/// Owns the footer button and popover for one window. The host supplies the engine-facing controller
/// and the key of the current Profile; the button shows only that Profile's downloads.
@MainActor
public final class DownloadsSidebar {
    let button = DownloadsButton()
    private let controller: DownloadsController
    private let popover: DownloadsPopover
    private var profileKey = ""

    public init(controller: DownloadsController) {
        self.controller = controller
        popover = DownloadsPopover(controller: controller)
        button.target = self
        button.action = #selector(toggle)
        refresh()
    }

    /// Call whenever the current Profile may have changed and from the controller's `onChange`.
    public func setProfileKey(_ key: String) {
        profileKey = key
        popover.updateProfile(key)
        refresh()
    }

    public func refresh() {
        let model = controller.model
        let active = model.activeItems(for: profileKey)
        button.isHidden = model.items(for: profileKey).isEmpty
        button.isActive = !active.isEmpty
        button.fraction = model.aggregateFraction(for: profileKey)
        button.hasUnseenFinish = model.hasUnseenFinish(for: profileKey) && !popover.isShown
        popover.reload()
    }

    @objc private func toggle() {
        popover.toggle(from: button, profileKey: profileKey)
        refresh()
    }
}
