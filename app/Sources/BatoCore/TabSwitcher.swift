import Foundation

/// One stop in the Ctrl-Tab switcher: a page, or a split pair counted as one.
public struct TabSwitchItem: Equatable, Identifiable, Sendable {
    public var entryIDs: [UUID]
    public var splitID: UUID?
    /// The entry to select when this item is chosen; for a pair, the member used most recently.
    public var selectionEntryID: UUID
    public var id: UUID { splitID ?? selectionEntryID }
}

/// Most-recently-used page order per workspace. Not persisted.
public struct RecentTabs: Equatable, Sendable {
    private var order: [UUID: [UUID]] = [:]
    public init() {}

    public mutating func record(entryID: UUID, workspaceID: UUID) {
        var list = order[workspaceID] ?? []
        list.removeAll { $0 == entryID }
        list.insert(entryID, at: 0)
        order[workspaceID] = list
    }

    /// Items of the current workspace, most recent first, then pages never selected in sidebar order.
    /// A pair is one item at the position of its most recent member. `unavailable` pages (closing) are left out.
    public func items(in state: BrowserState, unavailable: (UUID) -> Bool = { _ in false }) -> [TabSwitchItem] {
        let workspace = state.currentWorkspace
        let entries = state.visibleEntries.filter { !unavailable($0.id) }
        let known = Set(entries.map(\.id))
        let recent = (order[workspace.id] ?? []).filter(known.contains)
        let rest = entries.map(\.id).filter { !recent.contains($0) }
        var seenPairs = Set<UUID>()
        return (recent + rest).compactMap { id in
            guard let split = state.split(containingEntry: id) else {
                return TabSwitchItem(entryIDs: [id], splitID: nil, selectionEntryID: id)
            }
            guard seenPairs.insert(split.id).inserted else { return nil }
            return TabSwitchItem(entryIDs: [split.leftEntryID, split.rightEntryID], splitID: split.id, selectionEntryID: id)
        }
    }
}

/// The hold-Ctrl switcher. It selects an item as soon as Tab is pressed but only becomes visible after a short hold,
/// so a quick Ctrl-Tab tap toggles to the previous page without flashing the panel.
public struct TabSwitcherSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case pending, showing }
    public enum Outcome: Equatable, Sendable { case commit(TabSwitchItem), cancel }

    public let items: [TabSwitchItem]
    public private(set) var selectedIndex: Int
    public private(set) var phase: Phase = .pending

    /// Starts on the item after (or, for `step` < 0, before) the current page. Nil when there is nothing to switch to.
    public init?(items: [TabSwitchItem], step: Int) {
        guard items.count > 1, step != 0 else { return nil }
        self.items = items
        selectedIndex = step > 0 ? 1 : items.count - 1
    }

    public var selection: TabSwitchItem { items[selectedIndex] }

    public mutating func advance(step: Int) {
        selectedIndex = ((selectedIndex + step) % items.count + items.count) % items.count
    }

    public mutating func holdElapsed() { phase = .showing }

    public func controlReleased() -> Outcome { .commit(selection) }
    public func escapePressed() -> Outcome { .cancel }
}
