import Foundation

/// A tab in the top strip: favorites and pins draw as icons, tabs share the remaining width.
public struct TopTabItem: Equatable, Sendable {
    public let id: UUID
    public let isIconOnly: Bool

    public init(id: UUID, isIconOnly: Bool) {
        self.id = id
        self.isIconOnly = isIconOnly
    }
}

/// Horizontal layout of the top tab strip, in the strip's own coordinates (x from the left edge).
public enum TopTabStrip {
    public static let tabHeight: CGFloat = 32
    /// Centre line of the strip's controls and tabs: where AppKit centres the traffic lights, so they share a row.
    public static let rowCenterY: CGFloat = 31
    public static let iconTabWidth: CGFloat = 36
    public static let maxTabWidth: CGFloat = 220
    public static let minTabWidth: CGFloat = 34
    public static let gap: CGFloat = 4
    /// Extra room between the icon-only group and the tabs.
    public static let groupGap: CGFloat = 8

    /// Frames for `items` between `start` and `end`. Icon-only items keep their width; tabs shrink evenly
    /// from `maxTabWidth` down to `minTabWidth`, and any beyond that are clipped by the strip.
    public static func frames(for items: [TopTabItem], from start: CGFloat, to end: CGFloat) -> [CGRect] {
        let icons = items.filter(\.isIconOnly).count
        let tabs = items.count - icons
        var x = start
        let iconsWidth = CGFloat(icons) * (iconTabWidth + gap)
        let groupSpace = icons > 0 && tabs > 0 ? groupGap : 0
        let room = end - start - iconsWidth - groupSpace
        let width = tabs > 0 ? min(maxTabWidth, max(minTabWidth, room / CGFloat(tabs) - gap)) : maxTabWidth
        let y = rowCenterY - tabHeight / 2
        var seenTab = false
        return items.map { item in
            if !item.isIconOnly, !seenTab {
                seenTab = true
                x += groupSpace
            }
            let frame = CGRect(x: x, y: y, width: item.isIconOnly ? iconTabWidth : width.rounded(.down), height: tabHeight)
            x = frame.maxX + gap
            return frame
        }
    }

    /// The gap a dragged tab would drop into, 0 through `frames.count`, from the drag's horizontal position.
    public static func insertionSlot(atX x: CGFloat, among frames: [CGRect]) -> Int {
        frames.firstIndex { x < $0.midX } ?? frames.count
    }
}
