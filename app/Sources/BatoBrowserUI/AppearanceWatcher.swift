import AppKit

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// One place that turns "the look of the app changed" into a notification: the system or app
/// appearance, and the Increase Contrast and Reduce Transparency switches. Surfaces that cache a
/// resolved colour or a layer colour listen here instead of being read once at launch.
@MainActor
final class AppearanceWatcher {
    static let shared = AppearanceWatcher()
    static let didChange = Notification.Name("BatoAppearanceDidChange")

    private var appearanceObservation: NSKeyValueObservation?

    private init() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in AppearanceWatcher.post() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppearanceWatcher.post() }
        }
    }

    /// Call once at startup so the first change is not missed.
    static func start() { _ = shared }

    private static func post() { NotificationCenter.default.post(name: didChange, object: nil) }

    nonisolated static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
}
