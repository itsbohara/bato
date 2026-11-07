import AppKit

/// Visual constants and fills for sidebar rows and sheets. Fills are translucent label colors so
/// they read as a lift on any workspace tint, in light and dark, rather than a second palette.
enum SidebarStyle {
    static let rowHeight: CGFloat = 36
    static let tileHeight: CGFloat = 58
    static let tilesPerRow = 3
    static var rowFont: NSFont { NSFont.systemFont(ofSize: 14) }
    static var actionFont: NSFont { NSFont.systemFont(ofSize: 13) }
    static let commandBarRadius: CGFloat = 22
    static let commandBarRowHeight: CGFloat = 48
    static let commandBarSize = NSSize(width: 680, height: 470)

    static func rowFill(selected: Bool, hovered: Bool, tile: Bool) -> NSColor? {
        if selected { return NSColor.labelColor.withAlphaComponent(0.16) }
        if hovered { return NSColor.labelColor.withAlphaComponent(0.07) }
        if tile { return NSColor.labelColor.withAlphaComponent(0.12) }
        return nil
    }

    /// Top and bottom of the sidebar gradient. The workspace colour dominates, as in Dia; the system
    /// background only keeps the result from going neon. High contrast falls back to a faint wash.
    static func tint(_ accent: NSColor, dark: Bool, highContrast: Bool) -> (top: NSColor, bottom: NSColor) {
        let base = NSColor.windowBackgroundColor
        if highContrast {
            return (base.blended(withFraction: 0.08, of: accent) ?? base, base.blended(withFraction: 0.04, of: accent) ?? base)
        }
        let body = dark ? (accent.blended(withFraction: 0.35, of: .black) ?? accent) : accent
        let top = base.blended(withFraction: dark ? 0.8 : 0.55, of: body) ?? base
        let bottom = base.blended(withFraction: dark ? 0.6 : 0.4, of: body) ?? base
        return (top, bottom)
    }

    /// Initial-letter tile for pages without a favicon; the hue is stable per host.
    @MainActor
    static func letterIcon(for title: String, host: String?, size: CGFloat) -> NSImage {
        let letter = String((host?.replacingOccurrences(of: "www.", with: "").first ?? title.first ?? "?").uppercased())
        let seed = (host ?? title).unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        let color = NSColor(hue: CGFloat(seed % 360) / 360, saturation: 0.5, brightness: 0.62, alpha: 1)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: size * 0.28, yRadius: size * 0.28).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.55, weight: .semibold), .foregroundColor: NSColor.white]
            let text = NSAttributedString(string: letter, attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
            return true
        }
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
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 12, yRadius: 12).fill()
    }
}
