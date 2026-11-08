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
    /// Space between two panes; must equal `kNativePaneGap` in the engine layout.
    public static let paneGap: CGFloat = 10
    public static let paneCornerRadius: CGFloat = 10
    /// Blur of the soft glow around the focused pane's outline.
    public static let focusGlowBlur: CGFloat = 11
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

/// Geometry of the resize grabber drawn in the gap between two panes. Frames are in one coordinate space and the
/// first pane is the left or top one.
public enum SplitGrabber {
    public static let pillThickness: CGFloat = 2
    public static let pillLength: CGFloat = 24
    /// Extra reach on each side of the gap, so the thin gap is easy to hit.
    public static let hitSlop: CGFloat = 4
    public static let minimumRatio = 0.15

    public static func isHorizontal(first: CGRect, second: CGRect) -> Bool { first.maxX <= second.minX }

    public static func hitRect(first: CGRect, second: CGRect) -> CGRect {
        if isHorizontal(first: first, second: second) {
            return CGRect(x: first.maxX - hitSlop, y: min(first.minY, second.minY),
                          width: second.minX - first.maxX + 2 * hitSlop, height: max(first.maxY, second.maxY) - min(first.minY, second.minY))
        }
        return CGRect(x: min(first.minX, second.minX), y: first.maxY - hitSlop,
                      width: max(first.maxX, second.maxX) - min(first.minX, second.minX), height: second.minY - first.maxY + 2 * hitSlop)
    }

    /// A short fully rounded pill centred in the gap: vertical between side-by-side panes, horizontal between stacked ones.
    public static func pillRect(first: CGRect, second: CGRect) -> CGRect {
        let hit = hitRect(first: first, second: second)
        if isHorizontal(first: first, second: second) {
            return CGRect(x: hit.midX - pillThickness / 2, y: hit.midY - pillLength / 2, width: pillThickness, height: pillLength)
        }
        return CGRect(x: hit.midX - pillLength / 2, y: hit.midY - pillThickness / 2, width: pillLength, height: pillThickness)
    }

    /// The first pane's share of the space for a pointer position, keeping the gap centred under the pointer.
    public static func ratio(at point: CGPoint, first: CGRect, second: CGRect) -> Double {
        let horizontal = isHorizontal(first: first, second: second)
        let start = horizontal ? first.minX : first.minY
        let end = horizontal ? second.maxX : second.maxY
        let gap = horizontal ? second.minX - first.maxX : second.minY - first.maxY
        let total = end - start - gap
        guard total > 0 else { return 0.5 }
        let position = (horizontal ? point.x : point.y) - start - gap / 2
        return min(max(Double(position / total), minimumRatio), 1 - minimumRatio)
    }
}
