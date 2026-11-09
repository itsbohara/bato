import AppKit
import XCTest
import BatoCore
@testable import BatoBrowserUI

@MainActor
final class SpaceThemeStyleTests: XCTestCase {
    private func components(_ color: NSColor) -> [CGFloat] {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    }

    func testDefaultIntensityReproducesTheTintOfASpaceWithoutATheme() throws {
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let accent = NSColor(hex: "#527FAD")
        let before = SidebarStyle.tint(accent, appearance: dark)
        let themed = SidebarStyle.tint(accent, appearance: dark, intensity: SpaceTheme.defaultIntensity)
        XCTAssertEqual(components(before.top), components(themed.top))
        XCTAssertEqual(components(before.bottom), components(themed.bottom))
    }

    func testHigherIntensityMovesTheTintTowardsTheColour() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let accent = NSColor(hex: "#527FAD")
        let weak = SidebarStyle.tint(accent, appearance: light, intensity: 0.2).top
        let strong = SidebarStyle.tint(accent, appearance: light, intensity: 1).top
        XCTAssertLessThan(components(strong)[0], components(weak)[0])
    }

    func testModesMapToAppearances() {
        XCTAssertNil(SpaceTheme(color: "#527FAD").appearance)
        XCTAssertEqual(SpaceTheme(mode: .dark, stops: [.init(color: "#527FAD")]).appearance?.name, .darkAqua)
        XCTAssertEqual(SpaceTheme(mode: .light, stops: [.init(color: "#527FAD")]).appearance?.name, .aqua)
    }

    func testHexColourParsing() {
        XCTAssertEqual(components(NSColor(hex: "#FF8000")), [1, CGFloat(128) / 255, 0])
    }
}
