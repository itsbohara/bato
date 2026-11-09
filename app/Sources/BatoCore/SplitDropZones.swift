import CoreGraphics

/// The two drop areas offered over the page card while a sidebar tab is dragged. They sit at the card's
/// leading and trailing edges, small while the pointer is still in the sidebar and larger once it is over the page.
public enum SplitDropZones {
    public static let sides: [SplitSide] = [.left, .right]
    public static let armedSize = CGSize(width: 194, height: 327)
    public static let expandedSize = CGSize(width: 313, height: 520)
    public static let edgeInset: CGFloat = 24
    public static let cornerRadius: CGFloat = 20

    /// A zone never takes more than this share of the card, so a narrow window still has page between them.
    private static let maxWidthShare: CGFloat = 0.38
    private static let maxHeightShare: CGFloat = 0.8

    public static func frame(of side: SplitSide, in card: CGRect, expanded: Bool) -> CGRect? {
        guard sides.contains(side) else { return nil }
        let base = expanded ? expandedSize : armedSize
        let size = CGSize(width: min(base.width, card.width * maxWidthShare),
                          height: min(base.height, card.height * maxHeightShare))
        let x = side == .left ? card.minX + edgeInset : card.maxX - edgeInset - size.width
        return CGRect(x: x, y: card.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// The side whose zone holds `point`; the page between the zones is not a target.
    public static func side(at point: CGPoint, in card: CGRect, expanded: Bool) -> SplitSide? {
        sides.first { frame(of: $0, in: card, expanded: expanded)?.contains(point) == true }
    }
}
