import AppKit

/// Audio state per sidebar entry, fed by the engine and read by the rows' speaker badges.
@MainActor
public final class TabAudioCenter {
    public struct State: Equatable, Sendable {
        public var audible: Bool
        public var muted: Bool
        public var shown: Bool { audible || muted }
    }

    public static let shared = TabAudioCenter()
    public static let didChange = Notification.Name("BatoTabAudioDidChange")

    /// Mutes or unmutes the entry's live page; false when it has none.
    public var setMuted: ((UUID, Bool) -> Bool)?
    public private(set) var states: [UUID: State] = [:]

    public func update(entryID: UUID, audible: Bool, muted: Bool) {
        let next = State(audible: audible, muted: muted)
        guard states[entryID] != next else { return }
        states[entryID] = next.shown ? next : nil
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["entry": entryID])
    }

    public func toggleMute(entryID: UUID) {
        guard let state = states[entryID] else { return }
        _ = setMuted?(entryID, !state.muted)
    }
}

/// A speaker button on a page row while its tab plays sound or is muted; clicking toggles mute.
@MainActor
enum TabAudioBadge {
    static func attach(to row: NSView, entryID: UUID, tile: Bool, select: NSButton) {
        let badge = TabAudioButton(entryID: entryID, select: select)
        badge.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 18),
            badge.heightAnchor.constraint(equalToConstant: 18),
            badge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: tile ? -4 : -26),
            tile ? badge.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4)
                 : badge.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        badge.apply(row: row, tile: tile)
    }
}

@MainActor
private final class TabAudioButton: NSButton {
    private let entryID: UUID
    private let select: NSButton
    private var row: NSView?
    private var tile = false

    init(entryID: UUID, select: NSButton) {
        self.entryID = entryID
        self.select = select
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .recessed
        imagePosition = .imageOnly
        focusRingType = .none
        contentTintColor = .secondaryLabelColor
        setAccessibilityIdentifier("bato-audio-\(entryID.uuidString)")
        target = self
        action = #selector(toggle)
        // Selector observers are zeroing references on supported macOS versions.
        NotificationCenter.default.addObserver(self, selector: #selector(audioChanged(_:)),
                                               name: TabAudioCenter.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func apply(row: NSView, tile: Bool) {
        self.row = row
        self.tile = tile
        refresh()
    }

    @objc private func audioChanged(_ note: Notification) {
        if (note.userInfo?["entry"] as? UUID) == entryID { refresh() }
    }

    @objc private func toggle() { TabAudioCenter.shared.toggleMute(entryID: entryID) }

    private func refresh() {
        let state = TabAudioCenter.shared.states[entryID]
        isHidden = state == nil
        guard let state else { reserveTitleRoom(false); return }
        image = sidebarSymbol(state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 11)
        let title = state.muted ? "Unmute tab" : "Mute tab"
        toolTip = title
        setAccessibilityLabel(title)
        reserveTitleRoom(true)
    }

    /// The title must not run under the badge: widen the gap the row keeps before its close button.
    private func reserveTitleRoom(_ reserve: Bool) {
        guard !tile, let row,
              let trailing = row.constraints.first(where: {
                  $0.firstItem === select && $0.firstAttribute == .trailing && $0.secondAttribute == .leading
              }) else { return }
        trailing.constant = reserve ? -22 : -2
    }
}
