import CoreGraphics
import Foundation

/// Which controls a split pane's toolbar row shows.
public struct SplitPaneControls: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let sidebarToggle = SplitPaneControls(rawValue: 1)
    public static let back = SplitPaneControls(rawValue: 2)
    public static let forward = SplitPaneControls(rawValue: 4)
    public static let reload = SplitPaneControls(rawValue: 8)
    public static let host = SplitPaneControls(rawValue: 16)
    public static let extensions = SplitPaneControls(rawValue: 32)
    public static let splitMenu = SplitPaneControls(rawValue: 64)
    public static let close = SplitPaneControls(rawValue: 128)

    /// A focused pane shows everything; an unfocused one stays minimal until the pointer rests on its row.
    public static func visible(focused: Bool, hovered: Bool) -> SplitPaneControls {
        let minimal: SplitPaneControls = [.back, .forward, .host, .close]
        return focused || hovered ? minimal.union([.reload, .extensions, .splitMenu]) : minimal
    }

    /// Controls that dim instead of disappearing while their pane is unfocused.
    public static func dimmed(focused: Bool) -> SplitPaneControls {
        focused ? [] : [.back, .forward]
    }
}

public enum SplitPaneChrome {
    /// Height of each pane's toolbar row; must equal `kNativePaneToolbarHeight` in the engine layout.
    public static let toolbarHeight: CGFloat = 40
    public static let focusOutlineWidth: CGFloat = 2
    public static let hoverFadeDuration: TimeInterval = 0.12

    /// The sidebar toggle belongs to the leading pane (left or top) while the sidebar is hidden.
    public static func showsSidebarToggle(paneIndex: Int, sidebarHidden: Bool) -> Bool {
        paneIndex == 0 && sidebarHidden
    }

    /// Where a pane's page ends and the toolbar row above it begins, for a pane frame in the engine's coordinates.
    public static func toolbarFrame(ofPane pane: CGRect) -> CGRect {
        CGRect(x: pane.minX, y: pane.minY, width: pane.width, height: min(toolbarHeight, pane.height))
    }

    /// Which pane index a rect belongs to, by the divider side of the pair: first = left/top.
    public static func paneIndex(of entryID: UUID, in split: PageSplit) -> Int? {
        entryID == split.leftEntryID ? 0 : entryID == split.rightEntryID ? 1 : nil
    }
}
