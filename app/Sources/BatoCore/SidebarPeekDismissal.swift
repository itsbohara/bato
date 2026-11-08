/// When a hidden sidebar that floats over the page (peek) goes away again.
///
/// Programmatic focus requests reveal the sidebar without the pointer ever entering it, so
/// `mouseExited` cannot be the only way out: the pointer poll covers that case.
public enum SidebarPeekDismissal {
    public enum Event: Equatable {
        case pointerExited
        case pointerPoll
        case pageKey
        case pageClicked
        case windowResigned
    }

    public struct Context: Equatable {
        public var pointerInside: Bool
        /// Focus is in the sidebar, e.g. rename or search fields: leaving them to the pointer would eat typing.
        public var sidebarFocused: Bool
        /// The sidebar was revealed by a focus request (Cmd-T, a menu) and focus still sits on the control
        /// that request landed on: nobody chose to work in the sidebar.
        public var focusIsIncidental: Bool
        /// No sheet, modal or open menu owns the window; the overlay stays up beneath them.
        public var interactive: Bool

        public init(pointerInside: Bool, sidebarFocused: Bool, focusIsIncidental: Bool = false, interactive: Bool) {
            self.pointerInside = pointerInside
            self.sidebarFocused = sidebarFocused
            self.focusIsIncidental = focusIsIncidental
            self.interactive = interactive
        }
    }

    public static func shouldDismiss(on event: Event, _ context: Context) -> Bool {
        guard context.interactive else { return false }
        switch event {
        case .pointerExited:
            return !context.holdsFocus
        case .pointerPoll:
            return !context.pointerInside && !context.holdsFocus
        case .pageKey, .pageClicked, .windowResigned:
            return true
        }
    }
}

private extension SidebarPeekDismissal.Context {
    var holdsFocus: Bool { sidebarFocused && !focusIsIncidental }
}
