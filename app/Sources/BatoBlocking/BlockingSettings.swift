import Foundation

public enum BlockingSettingsError: Error, Equatable {
    case invalidHost
    case unsupportedVersion
}

/// Per-Profile blocking preferences. Exceptions are page hosts and cover their subdomains.
public struct BlockingSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public private(set) var version: Int
    public var enabled: Bool
    public private(set) var exceptions: [String]

    public init() {
        version = Self.currentVersion
        enabled = true
        exceptions = []
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw BlockingSettingsError.unsupportedVersion }
        enabled = try values.decode(Bool.self, forKey: .enabled)
        let raw = try values.decode([String].self, forKey: .exceptions)
        var hosts: [String] = []
        for entry in raw {
            guard let host = Self.normalizedHost(entry) else { throw BlockingSettingsError.invalidHost }
            if !hosts.contains(host) { hosts.append(host) }
        }
        exceptions = hosts.sorted()
    }

    /// Lowercased ASCII host without trailing dot, or nil. Internationalized hosts must be
    /// passed in punycode, which is what Chromium reports for page URLs.
    public static func normalizedHost(_ raw: String) -> String? {
        var host = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.utf8.count <= 253 else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard host.allSatisfy(allowed.contains) else { return nil }
        guard !host.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty) else { return nil }
        return host
    }

    public static func host(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host else { return nil }
        return normalizedHost(host)
    }

    /// The exception that covers `host`, if any: the host itself or a parent domain.
    public func exception(covering host: String) -> String? {
        guard let host = Self.normalizedHost(host) else { return nil }
        return exceptions.first { host == $0 || host.hasSuffix("." + $0) }
    }

    public func blocks(pageHost host: String) -> Bool {
        enabled && exception(covering: host) == nil
    }

    public mutating func addException(_ host: String) throws {
        guard let host = Self.normalizedHost(host) else { throw BlockingSettingsError.invalidHost }
        guard !exceptions.contains(host) else { return }
        exceptions = (exceptions + [host]).sorted()
    }

    public mutating func removeException(_ host: String) {
        guard let host = Self.normalizedHost(host) else { return }
        exceptions.removeAll { $0 == host }
    }
}
