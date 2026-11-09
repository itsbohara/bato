import AppKit
import BatoCore

extension SpaceTheme {
    /// Nil follows the system.
    var appearance: NSAppearance? {
        switch mode {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var primaryNSColor: NSColor { NSColor(hex: primaryColor) }
}

extension NSColor {
    convenience init(hex: String) {
        let value = hex.count == 7 ? UInt32(hex.dropFirst(), radix: 16) ?? 0x808080 : 0x808080
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// Paints a Space theme: the tint gradient, then grain over it.
@MainActor
enum ThemeFill {
    /// Draws into a flipped view's `rect`: a vertical blend for one colour, a diagonal one for several.
    static func draw(_ theme: SpaceTheme, in rect: NSRect, appearance: NSAppearance) {
        let tints = theme.stops.map { SidebarStyle.tint(NSColor(hex: $0.color), appearance: appearance, intensity: theme.intensity) }
        if tints.count == 1 {
            NSGradient(starting: tints[0].top, ending: tints[0].bottom)?.draw(in: rect, angle: -90)
        } else {
            NSGradient(colors: tints.map { $0.top.blended(withFraction: 0.5, of: $0.bottom) ?? $0.top })?.draw(in: rect, angle: -45)
        }
        drawGrain(theme.grain, in: rect)
    }

    /// The card's empty state sits a little above the tint.
    static func drawLifted(_ theme: SpaceTheme, in rect: NSRect, appearance: NSAppearance) {
        draw(theme, in: rect, appearance: appearance)
        (appearance.isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.08).setFill()
        rect.fill(using: .sourceOver)
    }

    static func drawGrain(_ amount: Double, in rect: NSRect) {
        guard amount > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(CGFloat(amount) * 0.35)
        NSColor(patternImage: noise).setFill()
        rect.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static let noise: NSImage = {
        let size = 128
        var generator = SystemRandomNumberGenerator()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<size {
            for y in 0..<size {
                let level = CGFloat.random(in: 0...1, using: &generator)
                rep.setColor(NSColor(white: level, alpha: 0.5), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }()
}
