import Foundation

/// A content-free record of data the importer dropped or repaired. `detail` never holds titles or URLs.
public struct ImportWarning: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case unsupportedURL, unknownItem, liveFolder
        case depthHoisted, splitFlattened, interleavingLost
        case cycle, duplicateItem, missingReference, excessiveNesting
        case truncatedName, nameDefaulted
        case droppedIcon, droppedTheme, duplicateFavorite
    }

    public var kind: Kind
    public var spaceID: String?
    public var detail: String?

    public init(_ kind: Kind, spaceID: String? = nil, detail: String? = nil) {
        self.kind = kind
        self.spaceID = spaceID
        self.detail = detail
    }
}

public struct ArcPage: Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: URL
}

public struct ArcSplit: Equatable, Sendable {
    public var id: String
    public var first: ArcPage
    public var second: ArcPage
}

public struct ArcFolder: Equatable, Sendable {
    public var id: String
    public var name: String
    public var children: [ArcNode]
}

public enum ArcNode: Equatable, Sendable {
    case page(ArcPage)
    case folder(ArcFolder)
    case split(ArcSplit)
}

public struct ArcProfile: Equatable, Sendable {
    public var key: String
    public var name: String
    public var favorites: [ArcPage]
}

public struct ArcSpace: Equatable, Sendable {
    public var id: String
    public var title: String
    public var profileKey: String
    public var colorHex: String?
    public var pinned: [ArcNode]
    public var today: [ArcNode]
}

/// Parsed Arc organization, already shaped to Bato's constraints (folder depth, URL scheme, split pairs).
public struct ArcStaging: Equatable, Sendable {
    public var sourceDigest: String
    public var profiles: [ArcProfile]
    public var spaces: [ArcSpace]
    public var warnings: [ImportWarning]

    public var warningCounts: [ImportWarning.Kind: Int] {
        warnings.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }
}

public enum ArcImportError: Error, Equatable, LocalizedError {
    case tooLarge
    case invalidJSON
    case missingSidebar

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The Arc file is larger than the importer accepts."
        case .invalidJSON: "The file is not valid Arc sidebar JSON. It may have been copied while Arc was writing it."
        case .missingSidebar: "No Arc spaces and items were found in this file."
        }
    }
}
