import Foundation

/// Whether Bato is the application macOS opens web links with. Registering is only ever done by an
/// explicit user action, so reading the state and changing it are separate calls.
public struct DefaultBrowser: Sendable {
    public enum Status: Equatable, Sendable { case isDefault, notDefault }

    public static let schemes = ["http", "https"]

    private let appURL: URL
    private let handler: @Sendable (String) -> URL?
    private let assign: @Sendable (String) async throws -> Void

    /// `handler` answers which application opens a scheme now; `assign` asks the system to make
    /// Bato that application (the system confirms with the user).
    public init(appURL: URL, handler: @escaping @Sendable (String) -> URL?,
                assign: @escaping @Sendable (String) async throws -> Void) {
        self.appURL = appURL
        self.handler = handler
        self.assign = assign
    }

    public var status: Status { Self.schemes.allSatisfy(isHandling) ? .isDefault : .notDefault }

    /// Registers Bato for the schemes it doesn't handle yet and stops at the first refusal.
    public func makeDefault() async throws {
        for scheme in Self.schemes where !isHandling(scheme) { try await assign(scheme) }
    }

    private func isHandling(_ scheme: String) -> Bool {
        handler(scheme)?.standardizedFileURL.path == appURL.standardizedFileURL.path
    }
}
