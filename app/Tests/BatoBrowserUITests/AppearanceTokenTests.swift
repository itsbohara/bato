import AppKit
import XCTest
@testable import BatoBrowserUI

@MainActor
final class AppearanceTokenTests: XCTestCase {
    private let palette = ["#B47879", "#527FAD", "#6D8B70", "#8975A8", "#B38847", "#76818F", "#FFD60A", "#FFFFFF", "#000000"]
    private let light = NSAppearance(named: .aqua)!
    private let dark = NSAppearance(named: .darkAqua)!

    private func color(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16)!
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    private func luminance(_ c: NSColor) -> Double {
        let rgb = c.usingColorSpace(.sRGB)!
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(rgb.redComponent) + 0.7152 * lin(rgb.greenComponent) + 0.0722 * lin(rgb.blueComponent)
    }

    /// Contrast of `foreground` (with its alpha) composited over an opaque `background`.
    private func contrast(_ foreground: NSColor, over background: NSColor) -> Double {
        let f = foreground.usingColorSpace(.sRGB)!
        let b = background.usingColorSpace(.sRGB)!
        let a = f.alphaComponent
        let mixed = NSColor(srgbRed: f.redComponent * a + b.redComponent * (1 - a),
                            green: f.greenComponent * a + b.greenComponent * (1 - a),
                            blue: f.blueComponent * a + b.blueComponent * (1 - a), alpha: 1)
        let l1 = luminance(mixed), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func resolved(_ c: NSColor, in appearance: NSAppearance) -> NSColor {
        var out = c
        appearance.performAsCurrentDrawingAppearance { out = c.usingColorSpace(.sRGB) ?? c }
        return out
    }

    func testTintResolvesPerAppearance() {
        let accent = color("#527FAD")
        let lightTint = SidebarStyle.tint(accent, appearance: light).top
        let darkTint = SidebarStyle.tint(accent, appearance: dark).top
        XCTAssertGreaterThan(luminance(lightTint), luminance(darkTint))
    }

    func testPrimaryTextIsLegibleOnEveryTintInBothAppearances() {
        for hex in palette {
            for appearance in [light, dark] {
                let tint = SidebarStyle.tint(color(hex), appearance: appearance)
                let label = resolved(.labelColor, in: appearance)
                for background in [tint.top, tint.bottom] {
                    XCTAssertGreaterThanOrEqual(contrast(label, over: background), 4.5,
                                                "\(hex) \(appearance.name.rawValue)")
                }
            }
        }
    }

    func testSecondaryTextStaysReadableOnTint() {
        for hex in palette {
            for appearance in [light, dark] {
                let tint = SidebarStyle.tint(color(hex), appearance: appearance)
                let secondary = resolved(.secondaryLabelColor, in: appearance)
                XCTAssertGreaterThanOrEqual(contrast(secondary, over: tint.top), 3, "\(hex) \(appearance.name.rawValue)")
            }
        }
    }

    func testFavoriteTileEdgeIsVisibleInBothAppearances() {
        let lightEdge = resolved(SidebarStyle.tileHairline, in: light)
        let darkEdge = resolved(SidebarStyle.tileHairline, in: dark)
        XCTAssertLessThan(luminance(lightEdge), 0.5)
        XCTAssertGreaterThan(luminance(darkEdge), 0.5)
    }

    func testLetterIconTextIsLegible() {
        for hue in stride(from: 0.0, to: 1.0, by: 0.1) {
            let fill = NSColor(hue: hue, saturation: 0.55, brightness: 0.52, alpha: 1)
            XCTAssertGreaterThanOrEqual(contrast(.white, over: fill), 3, "hue \(hue)")
        }
    }

    private func alpha(_ fill: NSColor?, in appearance: NSAppearance) -> CGFloat {
        guard let fill else { return 0 }
        return resolved(fill, in: appearance).alphaComponent
    }

    func testRowFillOrdersSelectedOverHoverOverRest() {
        for appearance in [light, dark] {
            let selected = alpha(SidebarStyle.rowFill(selected: true, hovered: true, tile: false), in: appearance)
            let hovered = alpha(SidebarStyle.rowFill(selected: false, hovered: true, tile: false), in: appearance)
            XCTAssertGreaterThan(selected, hovered)
            XCTAssertGreaterThan(hovered, 0)
            XCTAssertNil(SidebarStyle.rowFill(selected: false, hovered: false, tile: false))
        }
    }

    func testTilesRestFilledAndHoverBrightensThem() {
        for appearance in [light, dark] {
            let rest = alpha(SidebarStyle.rowFill(selected: false, hovered: false, tile: true), in: appearance)
            XCTAssertGreaterThan(rest, 0)
        }
    }

    func testRowWashIsWhiteOnDarkAndBlackOnLight() {
        let darkFill = resolved(SidebarStyle.rowFill(selected: true, hovered: false, tile: false)!, in: dark)
        let lightFill = resolved(SidebarStyle.rowFill(selected: true, hovered: false, tile: false)!, in: light)
        XCTAssertEqual(darkFill.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(lightFill.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(alpha(darkFill, in: dark), 0.13, accuracy: 0.01)
        XCTAssertEqual(alpha(lightFill, in: light), 0.07, accuracy: 0.01)
    }
}
