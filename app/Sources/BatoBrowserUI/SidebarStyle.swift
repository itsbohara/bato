import AppKit
import BatoCore

/// Visual constants and fills for sidebar rows and sheets. Fills are translucent label colors so
/// they read as a lift on any workspace tint, in light and dark, rather than a second palette.
enum SidebarStyle {
    static let rowHeight: CGFloat = 38
    static let tileHeight: CGFloat = 44
    static let tileIconSize: CGFloat = 20
    static let rowIconSize: CGFloat = 16
    static let tilesPerRow = 3
    static var rowFont: NSFont { NSFont.systemFont(ofSize: 13.5, weight: .medium) }
    static var actionFont: NSFont { NSFont.systemFont(ofSize: 13) }
    static let commandBarRadius: CGFloat = 12
    static let commandBarRowHeight: CGFloat = 50
    static let commandBarHeaderHeight: CGFloat = 56
    static let commandBarInset: CGFloat = 8
    static let commandBarMaxRows = 7
    static let commandBarWidth: CGFloat = 760
    static let commandBarTopFraction: CGFloat = 0.38

    /// The palette hangs from a fixed point: centred on the content card, top edge a set fraction down it
    /// (screen coordinates, y up). More rows only extend it downward.
    static func commandBarFrame(card: NSRect, height: CGFloat) -> NSRect {
        let top = card.maxY - card.height * commandBarTopFraction
        return NSRect(x: (card.midX - commandBarWidth / 2).rounded(), y: (top - height).rounded(),
                      width: commandBarWidth, height: height)
    }
    static let downloadsPopoverWidth: CGFloat = 320
    static let downloadsPopoverMaxListHeight: CGFloat = 360

    /// Arc's rows are soft fills of the foreground colour: white over dark, black over light. No stroke;
    /// Increase Contrast adds a hairline in the row view instead.
    private static func wash(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) {
            $0.isDark ? NSColor.white.withAlphaComponent(dark) : NSColor.black.withAlphaComponent(light)
        }
    }
    private static let selectedRowFill = wash(dark: 0.13, light: 0.07)
    private static let hoveredRowFill = wash(dark: 0.07, light: 0.04)
    /// Space header hover, a little stronger than a row's hover.
    static let headerHoverFill = wash(dark: 0.10, light: 0.06)
    private static let tileRestFill = wash(dark: 0.08, light: 0.06)

    static func rowFill(selected: Bool, hovered: Bool, tile: Bool) -> NSColor? {
        if selected { return selectedRowFill }
        if hovered { return hoveredRowFill }
        return tile ? tileRestFill : nil
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

    /// Dark-mode body colour: bright picks (yellow, white) would otherwise turn the sidebar light grey
    /// under white text, so brightness is capped before the blend.
    private static func darkened(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let capped = NSColor(hue: hue, saturation: saturation, brightness: min(brightness, 0.6), alpha: alpha)
        return capped.blended(withFraction: 0.35, of: .black) ?? capped
    }

    /// Top and bottom of the sidebar gradient for an appearance. The workspace colour dominates, as in
    /// Dia; the system background only keeps the result from going neon. Resolved under `appearance`, so
    /// the result is correct whichever appearance the caller happens to be drawing in. `intensity` scales how far
    /// the colour replaces the base; the default reproduces a Space saved before themes.
    static func tint(_ accent: NSColor, appearance: NSAppearance, intensity: Double = SpaceTheme.defaultIntensity) -> (top: NSColor, bottom: NSColor) {
        var result: (top: NSColor, bottom: NSColor)?
        appearance.performAsCurrentDrawingAppearance {
            let dark = appearance.isDark
            let base = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .windowBackgroundColor
            let hue = vivid(accent)
            let body = dark ? darkened(hue) : hue
            let strength = CGFloat(intensity / SpaceTheme.defaultIntensity)
            result = (base.blended(withFraction: min(1, (dark ? 0.8 : 0.55) * strength), of: body) ?? base,
                      base.blended(withFraction: min(1, (dark ? 0.6 : 0.4) * strength), of: body) ?? base)
        }
        return result ?? (.windowBackgroundColor, .windowBackgroundColor)
    }

    /// Tile edge: white only shows on dark; light mode needs a dark hairline.
    static let tileHairline = NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.08) }
    /// Card fill in Settings.
    static let cardFill = NSColor.labelColor.withAlphaComponent(0.06)

    /// Initial-letter tile for pages without a favicon. IP and localhost hosts say nothing about the
    /// page, so the title supplies the letter; the hue comes from the full URL so tiles on one host differ.
    @MainActor
    static func letterIcon(for title: String, url: URL, size: CGFloat) -> NSImage {
        let spec = FaviconFallback.spec(title: title, url: url)
        let color = NSColor(hue: spec.hue, saturation: 0.55, brightness: 0.52, alpha: 1)
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
