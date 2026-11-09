import Foundation

/// The app's light or dark look; `system` follows macOS.
public enum AppAppearance: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, bringOver, makeItYours, done
}

/// Where the first-run card is. Skipping or finishing both end it; the caller marks it complete either way.
public struct OnboardingFlow: Equatable, Sendable {
    public private(set) var step: OnboardingStep = .welcome
    public private(set) var isEnded = false

    public init() {}

    /// The welcome step has nothing to go back to, and the last step only closes the card.
    public var canGoBack: Bool { step != .welcome && step != .done }

    public mutating func advance() {
        guard !isEnded else { return }
        if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next } else { isEnded = true }
    }

    public mutating func goBack() {
        guard canGoBack, let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    public mutating func skip() { isEnded = true }
}

public enum TabLayout: String, CaseIterable, Sendable {
    case sidebar, sidebarRight, top

    public var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .sidebarRight: "Sidebar on Right"
        case .top: "Top"
        }
    }

    /// The engine reserves the sidebar's strip on the left of the window and owns the toolbar row,
    /// so neither a mirrored sidebar nor a top tab strip can be drawn from Swift alone.
    public var isAvailable: Bool { self == .sidebar }
}

public enum NewTabStyle: String, CaseIterable, Sendable {
    case popup, fullPage

    public var title: String { self == .popup ? "Popup" : "Full Page" }

    /// Cmd-T only opens the command bar popup.
    public var isAvailable: Bool { self == .popup }
}

public struct OnboardingThemePreset: Equatable, Sendable {
    public let name: String
    public let theme: SpaceTheme?

    /// "None" plus eight named swatches from the first page of `SpaceTheme.presetPages`.
    public static let all: [OnboardingThemePreset] = {
        let names = ["Linen", "Rose", "Lilac", "Coral", "Amber", "Butter", "Mint", "Sky"]
        return [OnboardingThemePreset(name: "None", theme: nil)]
            + zip(names, SpaceTheme.presetPages[0]).map { OnboardingThemePreset(name: $0, theme: SpaceTheme(stops: $1.stops)) }
    }()
}

/// What "Make it yours" holds before Continue. Unavailable options cannot be chosen.
public struct OnboardingChoices: Equatable, Sendable {
    public private(set) var tabLayout = TabLayout.sidebar
    public private(set) var newTab = NewTabStyle.popup
    public private(set) var themeIndex = 0
    public var appearance = AppAppearance.system

    public init() {}

    @discardableResult
    public mutating func select(_ layout: TabLayout) -> Bool {
        guard layout.isAvailable else { return false }
        tabLayout = layout
        return true
    }

    @discardableResult
    public mutating func select(_ style: NewTabStyle) -> Bool {
        guard style.isAvailable else { return false }
        newTab = style
        return true
    }

    @discardableResult
    public mutating func selectTheme(at index: Int) -> Bool {
        guard OnboardingThemePreset.all.indices.contains(index) else { return false }
        themeIndex = index
        return true
    }

    /// Nil for "None": the Space keeps the look it has.
    public var theme: SpaceTheme? { OnboardingThemePreset.all[themeIndex].theme }
}
