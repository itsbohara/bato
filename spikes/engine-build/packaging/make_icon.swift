import AppKit

// Usage: swift make_icon.swift <output.iconset directory>
// Renders the placeholder Bato mark at every size iconutil expects.

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let inset = size * 0.0977
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.13, green: 0.42, blue: 0.48, alpha: 1),
                        NSColor(red: 0.07, green: 0.16, blue: 0.30, alpha: 1)])!
        .draw(in: shape, angle: -90)

    let font = NSFont.systemFont(ofSize: tile.height * 0.66, weight: .heavy)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
    let glyph = NSAttributedString(string: "B", attributes: [.font: rounded, .foregroundColor: NSColor.white])
    let extent = glyph.size()
    glyph.draw(at: NSPoint(x: tile.midX - extent.width / 2, y: tile.midY - extent.height / 2 - tile.height * 0.01))

    return bitmap.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
