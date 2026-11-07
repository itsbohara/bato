import AppKit

/// Visual constants and fills for sidebar rows and sheets. Fills are translucent label colors so
/// they read as a lift on any workspace tint, in light and dark, rather than a second palette.
enum SidebarStyle {
    static let rowHeight: CGFloat = 36
    static let tileHeight: CGFloat = 46
    static let tilesPerRow = 3
    static var rowFont: NSFont { NSFont.systemFont(ofSize: 14) }
    static var headingFont: NSFont { NSFont.systemFont(ofSize: 11, weight: .medium) }
    static var actionFont: NSFont { NSFont.systemFont(ofSize: 13) }
    static let commandBarRadius: CGFloat = 20
    static let commandBarRowHeight: CGFloat = 44

    static func rowFill(selected: Bool, hovered: Bool, tile: Bool) -> NSColor? {
        if selected { return NSColor.labelColor.withAlphaComponent(0.13) }
        if hovered { return NSColor.labelColor.withAlphaComponent(0.07) }
        if tile { return NSColor.labelColor.withAlphaComponent(0.08) }
        return nil
    }

    /// Sizes a sheet to its content so short forms do not end in blank space.
    @MainActor
    static func fitSheet(_ window: NSWindow, to stack: NSView, horizontalInset: CGFloat = 20, verticalInset: CGFloat = 18) {
        window.contentView?.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        window.setContentSize(NSSize(width: window.contentRect(forFrameRect: window.frame).width,
                                     height: ceil(fitting.height + verticalInset * 2)))
    }
}

/// Command bar results: a rounded inset selection instead of the full-width system bar.
@MainActor
final class RoundedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 10, yRadius: 10).fill()
    }
}
