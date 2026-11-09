import Foundation

/// A Space's look: one to three colours blended across the window, a light or dark scheme for the sidebar,
/// how strongly the colours replace the neutral base, and film grain. A Space saved before themes existed
/// has only a colour and reads as `init(color:)`.
public struct SpaceTheme: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case auto, light, dark }

    /// A colour and where its handle sits in the picker's field, a unit disc with y pointing down.
    public struct Stop: Codable, Equatable, Sendable {
        public var color: String
        public var x: Double
        public var y: Double

        public init(color: String, x: Double, y: Double) {
            self.color = color.uppercased()
            self.x = x
            self.y = y
        }

        /// A stop at the field position that best reproduces `color`.
        public init(color: String) {
            let position = SpaceTheme.fieldPosition(ofColor: color)
            self.init(color: color, x: position.x, y: position.y)
        }
    }

    public struct Preset: Equatable, Sendable {
        public var stops: [Stop]
    }

    public static let maxStops = 3
    /// The strength at which a colour reads exactly as Spaces did before themes had a strength.
    public static let defaultIntensity = 0.5

    public var mode: Mode
    public var stops: [Stop]
    public var intensity: Double
    public var grain: Double

    public init(mode: Mode = .auto, stops: [Stop], intensity: Double = SpaceTheme.defaultIntensity, grain: Double = 0) {
        self.mode = mode
        self.stops = stops
        self.intensity = intensity
        self.grain = grain
    }

    public init(color: String) {
        self.init(stops: [Stop(color: color)])
    }

    public var primaryColor: String { stops[0].color }

    public var isValid: Bool {
        (1...Self.maxStops).contains(stops.count)
            && stops.allSatisfy { Self.isHex($0.color) && $0.x.isFinite && $0.y.isFinite && $0.x * $0.x + $0.y * $0.y <= 1.0001 }
            && (0...1).contains(intensity) && (0...1).contains(grain)
    }

    /// Adds a colour beside the last one. False at the limit.
    @discardableResult
    public mutating func addStop() -> Bool {
        guard stops.count < Self.maxStops, let last = stops.last else { return false }
        let angle = atan2(last.y, last.x) + 2 * .pi / 3
        let radius = max(0.35, min(0.75, hypot(last.x, last.y)))
        let x = radius * cos(angle), y = radius * sin(angle)
        stops.append(Stop(color: Self.fieldColor(x: x, y: y), x: x, y: y))
        return true
    }

    /// Removes a colour; the last one cannot go.
    @discardableResult
    public mutating func removeStop(at index: Int) -> Bool {
        guard stops.count > 1, stops.indices.contains(index) else { return false }
        stops.remove(at: index)
        return true
    }

    /// Moves a handle, holding it inside the field, and recolours it from the spot.
    public mutating func moveStop(at index: Int, toX x: Double, y: Double) {
        guard stops.indices.contains(index) else { return }
        let length = hypot(x, y)
        let clamped = length > 1 ? (x: x / length, y: y / length) : (x: x, y: y)
        stops[index] = Stop(color: Self.fieldColor(x: clamped.x, y: clamped.y), x: clamped.x, y: clamped.y)
    }

    // MARK: Field

    /// Hue follows the angle around the field, lightness the distance from the centre: black in the middle,
    /// pure colour halfway out, white at the rim.
    public static func fieldColor(x: Double, y: Double) -> String {
        var hue = atan2(y, x) * 180 / .pi
        if hue < 0 { hue += 360 }
        return hex(fromHue: hue, saturation: 1, lightness: min(hypot(x, y), 1))
    }

    public static func fieldPosition(ofColor color: String) -> (x: Double, y: Double) {
        guard let (hue, _, lightness) = hsl(ofHex: color) else { return (0, 0) }
        let angle = hue * .pi / 180
        return (lightness * cos(angle), lightness * sin(angle))
    }

    static func isHex(_ value: String) -> Bool {
        value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }

    static func hex(fromHue hue: Double, saturation: Double, lightness: Double) -> String {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (r, g, b) = (chroma, second, 0)
        case 1: (r, g, b) = (second, chroma, 0)
        case 2: (r, g, b) = (0, chroma, second)
        case 3: (r, g, b) = (0, second, chroma)
        case 4: (r, g, b) = (second, 0, chroma)
        default: (r, g, b) = (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        return String(format: "#%02X%02X%02X", Int(((r + match) * 255).rounded()),
                      Int(((g + match) * 255).rounded()), Int(((b + match) * 255).rounded()))
    }

    static func hsl(ofHex value: String) -> (hue: Double, saturation: Double, lightness: Double)? {
        guard isHex(value), let packed = UInt32(value.dropFirst(), radix: 16) else { return nil }
        let r = Double((packed >> 16) & 255) / 255, g = Double((packed >> 8) & 255) / 255, b = Double(packed & 255) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        let lightness = (high + low) / 2
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch high {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    // MARK: Presets

    /// Four pages of nine swatches: solid, gradient, pastel and deep.
    public static let presetPages: [[Preset]] = [
        solids(["#F2EFEA", "#E1B4C6", "#A88CAA", "#D68681", "#E3A376", "#EEDD83", "#A4E3AE", "#A2C3DD", "#7B7B98"]),
        gradients([("#E8B4B8", "#9AA9D8"), ("#E1B4C6", "#7B7B98"), ("#A88CAA", "#E3A376"), ("#D68681", "#EEDD83"),
                   ("#E3A376", "#A88CAA"), ("#EEDD83", "#A4E3AE"), ("#A4E3AE", "#A2C3DD"), ("#A2C3DD", "#A88CAA"),
                   ("#7B7B98", "#D68681")]),
        solids(["#FFFFFF", "#F5DDF0", "#E0D0F0", "#F0CCCC", "#F5DFCF", "#FFF3D0", "#D8F0E0", "#CFE3F8", "#BDB8E0"]),
        solids(["#4B3A7A", "#7A3A70", "#8A4A44", "#A5733E", "#D6B95A", "#D8D6B0", "#8DAE8A", "#2F5A3C", "#2A3A80"])
    ]

    private static func solids(_ colors: [String]) -> [Preset] {
        colors.map { Preset(stops: [Stop(color: $0)]) }
    }

    private static func gradients(_ pairs: [(String, String)]) -> [Preset] {
        pairs.map { Preset(stops: [Stop(color: $0.0), Stop(color: $0.1)]) }
    }
}
