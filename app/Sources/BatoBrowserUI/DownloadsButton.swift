import AppKit
import BatoCore

/// Sidebar footer button: a download arrow inside a progress ring that fills while downloads run,
/// with a dot when one finished unseen. Hidden while the current Profile has no downloads, as in Arc.
@MainActor
final class DownloadsButton: NSButton {
    var fraction: Double? { didSet { needsDisplay = true } }
    var isActive = false { didSet { needsDisplay = true } }
    var hasUnseenFinish = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .recessed
        imagePosition = .imageOnly
        image = sidebarSymbol("arrow.down", size: 12, weight: .semibold)
        contentTintColor = .secondaryLabelColor
        focusRingType = .none
        toolTip = "Downloads"
        setAccessibilityLabel("Downloads")
        setAccessibilityIdentifier("bato-downloads-button")
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let ring = bounds.insetBy(dx: 3.5, dy: 3.5)
        let track = NSBezierPath(ovalIn: ring)
        track.lineWidth = 1.5
        NSColor.labelColor.withAlphaComponent(AppearanceWatcher.increaseContrast ? 0.4 : (isActive ? 0.18 : 0.1)).setStroke()
        track.stroke()
        if isActive {
            NSColor.controlAccentColor.setStroke()
            let arc = NSBezierPath()
            let center = NSPoint(x: ring.midX, y: ring.midY)
            if let fraction {
                arc.appendArc(withCenter: center, radius: ring.width / 2, startAngle: 90,
                              endAngle: 90 - 360 * CGFloat(fraction), clockwise: true)
            } else {
                arc.appendArc(withCenter: center, radius: ring.width / 2, startAngle: 90, endAngle: -30, clockwise: true)
            }
            arc.lineWidth = 1.5
            arc.lineCapStyle = .round
            arc.stroke()
        }
        if hasUnseenFinish {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 9, y: bounds.maxY - 9, width: 6, height: 6)).fill()
        }
    }
}
