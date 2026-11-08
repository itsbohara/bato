import AppKit
import BatoCore

/// What one switcher card shows for a page.
struct TabSwitchRowContent {
    var title: String
    var host: String
    var icon: NSImage
}

/// The floating Ctrl-Tab strip: one card per recent tab, a split pair as one card. A non-activating panel centred
/// on the window, so the page keeps focus and Control stays held with events still reaching the window's monitor.
@MainActor
final class TabSwitcherPanel {
    nonisolated static let maxVisibleCards = 6
    nonisolated static let cardWidth: CGFloat = 181
    nonisolated static let cardHeight: CGFloat = 158
    nonisolated static let padding: CGFloat = 15

    private var panel: NSPanel?
    private let describe: (UUID) -> TabSwitchRowContent?

    init(describe: @escaping (UUID) -> TabSwitchRowContent?) { self.describe = describe }

    var isShowing: Bool { panel != nil }

    /// Cards to draw, keeping the selection inside the window of `maxVisibleCards`.
    nonisolated static func visibleRange(count: Int, selected: Int) -> Range<Int> {
        guard count > maxVisibleCards else { return 0..<count }
        let start = min(max(selected - maxVisibleCards / 2, 0), count - maxVisibleCards)
        return start..<(start + maxVisibleCards)
    }

    func show(_ session: TabSwitcherSession, over window: NSWindow) {
        let panel = self.panel ?? makePanel(over: window)
        self.panel = panel
        let range = Self.visibleRange(count: session.items.count, selected: session.selectedIndex)
        let size = NSSize(width: CGFloat(range.count) * Self.cardWidth + 2 * Self.padding,
                          height: Self.cardHeight + 2 * Self.padding)
        let content = TabSwitcherBackground(frame: NSRect(origin: .zero, size: size))
        content.setAccessibilityIdentifier("bato-tab-switcher")
        for (slot, index) in range.enumerated() {
            let card = TabSwitcherCard(selected: index == session.selectedIndex,
                                       content: session.items[index].entryIDs.compactMap(describe))
            card.setAccessibilityIdentifier("bato-switcher-card-\(index)")
            card.frame = NSRect(x: Self.padding + CGFloat(slot) * Self.cardWidth, y: Self.padding,
                                width: Self.cardWidth, height: Self.cardHeight)
            content.addSubview(card)
        }
        panel.contentView = content
        let frame = window.frame
        panel.setFrame(NSRect(x: (frame.midX - size.width / 2).rounded(), y: (frame.midY - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
    }

    private func makePanel(over window: NSWindow) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.level = window.level
        return panel
    }
}

/// Near-opaque neutral plate with a hairline border, large radius.
@MainActor
private final class TabSwitcherBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.isDark
        let plate = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 28, yRadius: 28)
        (dark ? NSColor(srgbRed: 0.102, green: 0.098, blue: 0.098, alpha: 0.98) : NSColor(white: 0.97, alpha: 0.98)).setFill()
        plate.fill()
        (dark ? NSColor(srgbRed: 0.24, green: 0.24, blue: 0.24, alpha: 1) : NSColor.black.withAlphaComponent(0.15)).setStroke()
        plate.lineWidth = 1
        plate.stroke()
    }
}

/// One stop: a preview plate with the favicon and, for a single page, the title underneath. A pair shows two
/// plates side by side and two favicons, no title.
@MainActor
private final class TabSwitcherCard: NSView {
    private let selected: Bool
    private let content: [TabSwitchRowContent]

    init(selected: Bool, content: [TabSwitchRowContent]) {
        self.selected = selected
        self.content = content
        super.init(frame: .zero)
        setAccessibilityLabel(content.map(\.title).joined(separator: " and "))
        setAccessibilityValue(selected ? "selected" : nil)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.isDark
        if selected {
            (dark ? NSColor(srgbRed: 0.259, green: 0.247, blue: 0.510, alpha: 1) : NSColor.controlAccentColor.withAlphaComponent(0.25)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11).fill()
        }
        let isPair = content.count > 1
        let plateWidth: CGFloat = isPair ? 73 : 150
        let plateTop = bounds.height - 12
        let plateHeight: CGFloat = 100
        let totalWidth = CGFloat(content.count) * plateWidth + CGFloat(max(content.count - 1, 0)) * 4
        var x = (bounds.width - totalWidth) / 2
        for page in content {
            let plate = NSRect(x: x, y: plateTop - plateHeight, width: plateWidth, height: plateHeight)
            // The page itself is not captured; the plate stands in for its thumbnail.
            (dark ? NSColor(srgbRed: 0.137, green: 0.141, blue: 0.161, alpha: 1) : NSColor(white: 1, alpha: 1)).setFill()
            NSBezierPath(roundedRect: plate, xRadius: 6, yRadius: 6).fill()
            let icon: CGFloat = isPair ? 24 : 32
            page.icon.draw(in: NSRect(x: plate.midX - icon / 2, y: plate.midY - icon / 2, width: icon, height: icon))
            x += plateWidth + 4
        }
        let labelColor = dark ? NSColor.white : NSColor.black
        if isPair {
            // Both titles, one row each, under the two plates.
            for (row, page) in content.enumerated() {
                let rowY = 26 - CGFloat(row) * 20
                page.icon.draw(in: NSRect(x: 16, y: rowY + 2, width: 14, height: 14))
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byTruncatingTail
                NSAttributedString(string: page.title, attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: labelColor,
                    .paragraphStyle: style]).draw(in: NSRect(x: 36, y: rowY, width: bounds.width - 36 - 14, height: 18))
            }
        } else if let page = content.first {
            page.icon.draw(in: NSRect(x: 16, y: 20 - 8 + 4, width: 16, height: 16))
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: page.title, attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: labelColor,
                .paragraphStyle: style]).draw(in: NSRect(x: 38, y: 11, width: bounds.width - 38 - 14, height: 20))
        }
    }
}
