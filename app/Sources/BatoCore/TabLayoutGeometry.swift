import Foundation

public enum SidebarEdge: Sendable { case left, right }

public extension TabLayout {
    /// The window edge the sidebar docks to; nil when tabs sit in a strip above the page.
    var sidebarEdge: SidebarEdge? {
        switch self {
        case .sidebar: .left
        case .sidebarRight: .right
        case .top: nil
        }
    }

    /// Fullscreen has no room for a strip over the page; top tabs fall back to the floating sidebar there.
    func displayed(inFullscreen fullscreen: Bool) -> TabLayout {
        fullscreen && self == .top ? .sidebar : self
    }

    /// Value of the engine's layout argument; must match `NativeTabLayout` in the engine overlay.
    var engineCode: Int32 {
        switch self {
        case .sidebar: 0
        case .sidebarRight: 1
        case .top: 2
        }
    }

    var symbolName: String {
        switch self {
        case .sidebar, .top: "sidebar.left"
        case .sidebarRight: "sidebar.right"
        }
    }
}

/// Where the content card and the tint around it fall inside the window, in flipped coordinates (y down).
public enum ChromeGeometry {
    /// Gutter around the card; must equal `kNativeCardMargin` in the engine overlay.
    public static let cardMargin: CGFloat = 8
    /// Height of the tab strip above the card in the top layout; must equal `kNativeTopStripHeight` in the engine overlay.
    public static let topStripHeight: CGFloat = 54
    /// Bounds of Chrome's toolbar segment at the trailing end of the strip's row; must equal `NativeTopToolbarWidthFor` in the engine overlay.
    public static let topToolbarMinWidth = 360
    public static let topToolbarMaxWidth = 640

    /// Width of Chrome's toolbar in the top layout: 40% of the window within the bounds, and never more than 60% so the tabs keep room.
    /// Integer arithmetic so the engine, which truncates the same way, agrees to the point.
    public static func topToolbarWidth(forWindowWidth windowWidth: CGFloat) -> CGFloat {
        let width = Int(max(0, windowWidth))
        let share = min(max(width * 2 / 5, topToolbarMinWidth), topToolbarMaxWidth)
        return CGFloat(min(share, width * 3 / 5))
    }

    /// `reservation` is the docked sidebar's width, 0 when it is hidden or floating.
    public static func cardRect(in size: CGSize, layout: TabLayout, reservation: CGFloat) -> CGRect {
        let margin = cardMargin
        let x: CGFloat, top: CGFloat, width: CGFloat
        switch layout {
        case .sidebar:
            x = reservation + margin
            top = margin
            width = size.width - reservation - 2 * margin
        case .sidebarRight:
            x = margin
            top = margin
            width = size.width - reservation - 2 * margin
        case .top:
            x = margin
            top = topStripHeight
            width = size.width - 2 * margin
        }
        return CGRect(x: x, y: top, width: max(0, width), height: max(0, size.height - top - margin))
    }

    /// The part of the window the native sidebar or strip paints for itself, which the tint must not cover.
    /// The top strip stops where Chrome's toolbar segment begins; the tint shows behind that toolbar.
    public static func coverRect(in size: CGSize, layout: TabLayout, coverWidth: CGFloat) -> CGRect {
        switch layout {
        case .sidebar: CGRect(x: 0, y: 0, width: coverWidth, height: size.height)
        case .sidebarRight: CGRect(x: max(0, size.width - coverWidth), y: 0, width: coverWidth, height: size.height)
        case .top: CGRect(x: 0, y: 0, width: size.width - topToolbarWidth(forWindowWidth: size.width), height: min(topStripHeight, size.height))
        }
    }
}
