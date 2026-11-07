import Foundation

/// Connects an engine to the per-Profile model and republishes changes to the sidebar.
/// Actions go to the engine and the model changes only when its events say so.
@MainActor
public final class DownloadsController {
    public private(set) var model = DownloadsModel()
    public var onChange: (() -> Void)?
    private let engine: DownloadsEngine

    public init(engine: DownloadsEngine) {
        self.engine = engine
        engine.onEvent = { [weak self] event in self?.receive(event) }
        engine.requestSnapshot()
    }

    public func receive(_ event: DownloadEvent) {
        model.apply(event)
        onChange?()
    }

    @discardableResult
    public func perform(_ action: DownloadAction, on item: DownloadItem) -> Bool {
        engine.perform(action, id: item.id, profileKey: item.profileKey)
    }

    public func markSeen(_ profileKey: String) {
        model.markSeen(profileKey)
        onChange?()
    }

    public func clearFinished(for profileKey: String) {
        model.clearFinished(for: profileKey)
        onChange?()
    }
}
