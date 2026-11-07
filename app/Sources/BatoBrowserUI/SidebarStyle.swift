import AppKit
import BatoCore

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

    /// Lifts a stored workspace colour to a hue that survives blending: muted picks like slate blue or
    /// sage would otherwise vanish into the dark system background. Truly neutral greys stay neutral.
    static func vivid(_ accent: NSColor) -> NSColor {
        guard let rgb = accent.usingColorSpace(.sRGB) else { return accent }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let boosted = saturation < 0.05 ? saturation : max(saturation, 0.6)
        return NSColor(hue: hue, saturation: boosted, brightness: max(brightness, 0.8), alpha: alpha)
    }

    /// Top and bottom of the sidebar gradient. The workspace colour dominates, as in Dia; the system
    /// background only keeps the result from going neon. Increase Contrast keeps a lighter wash so text
    /// stays legible, but still clearly coloured.
    static func tint(_ accent: NSColor, dark: Bool, highContrast: Bool) -> (top: NSColor, bottom: NSColor) {
        let base = NSColor.windowBackgroundColor
        let hue = vivid(accent)
        if highContrast {
            return (base.blended(withFraction: dark ? 0.3 : 0.2, of: hue) ?? base,
                    base.blended(withFraction: dark ? 0.2 : 0.12, of: hue) ?? base)
        }
        let body = dark ? (hue.blended(withFraction: 0.35, of: .black) ?? hue) : hue
        let top = base.blended(withFraction: dark ? 0.8 : 0.55, of: body) ?? base
        let bottom = base.blended(withFraction: dark ? 0.6 : 0.4, of: body) ?? base
        return (top, bottom)
    }

    /// Initial-letter tile for pages without a favicon. IP and localhost hosts say nothing about the
    /// page, so the title supplies the letter; the hue comes from the full URL so tiles on one host differ.
    @MainActor
    static func letterIcon(for title: String, url: URL, size: CGFloat) -> NSImage {
        let spec = FaviconFallback.spec(title: title, url: url)
        let color = NSColor(hue: spec.hue, saturation: 0.5, brightness: 0.62, alpha: 1)
        let letter = spec.letter
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
