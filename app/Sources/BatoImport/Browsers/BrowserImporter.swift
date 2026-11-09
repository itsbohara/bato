import Foundation

/// Read side of "Bring everything over": counts for the toggle subtitles, then the full snapshot.
/// Everything is read-only against the browser's data: SQLite files are copied to a temp directory
/// first, JSON/plist files are read directly. Passwords, cookies and form data are never read.
public struct BrowserImporter: Sendable {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var detector: BrowserDetector { BrowserDetector(home: home) }

    /// Cheap counts per supported item for the subtitles ("Favorites - 48 sites", "History - 2,019 pages").
    /// A blocked Safari folder yields `.needsFullDiskAccess` for every item instead of an error.
    public func counts(_ source: ImportSource, profile: DetectedProfile) -> [ImportItem: ItemAvailability] {
        let items = BrowserLocations.supportedItems(source)
        if source == .safari, !SafariReader.hasFullDiskAccess(folder: profile.directory) {
            return Dictionary(uniqueKeysWithValues: items.map { ($0, .needsFullDiskAccess) })
        }
        var result: [ImportItem: ItemAvailability] = [:]
        let marks = bookmarkSet(source, profile)
        let staging = spacesStaging(source, profile)
        for item in items {
            switch item {
            case .favorites:
                result[item] = availability(source, favoritesCount(source, marks: marks, staging: staging))
            case .bookmarks:
                result[item] = availability(source, marks?.map { $0.tree.reduce(0) { $0 + $1.pageCount } })
            case .spaces:
                result[item] = availability(source, staging?.map { $0?.spaces.count ?? 0 })
            case .history:
                result[item] = availability(source, Result { try historyCount(source, profile) }.mapError(asReadError))
            }
        }
        return result
    }

    /// Reads the selected items. Throws `ImportReadError.permissionDenied` for a blocked Safari folder.
    public func read(_ source: ImportSource, profile: DetectedProfile, items: Set<ImportItem>) throws -> BrowserSnapshot {
        var snapshot = BrowserSnapshot(source: source, profileID: profile.id)
        snapshot.notes = BrowserLocations.notes(source)
        do {
            // Arc keeps nothing in Chromium bookmarks; its Favorites live in the sidebar file.
            if source != .arc, items.contains(.favorites) || items.contains(.bookmarks) {
                let marks = try bookmarkTree(source, profile)
                if items.contains(.favorites) { snapshot.favorites = marks.favorites }
                if items.contains(.bookmarks) { snapshot.bookmarks = marks.tree }
            }
            if items.contains(.favorites) || items.contains(.spaces), source == .arc || source == .zen {
                if var staging = try spacesStagingThrowing(source, profile) {
                    if items.contains(.favorites) { snapshot.favorites += mergedFavorites(staging) }
                    staging.profiles = staging.profiles.map { ArcProfile(key: $0.key, name: $0.name, favorites: []) }
                    if items.contains(.spaces) { snapshot.spaces = staging }
                }
            }
            if items.contains(.history) { snapshot.history = try history(source, profile) }
        } catch let error as ImportReadError {
            throw source == .safari ? error : (error == .permissionDenied ? .unreadable : error)
        }
        snapshot.favorites = unique(snapshot.favorites)
        return snapshot
    }

    /// Reads a bookmarks HTML export the user chose (the route for Orion).
    public func readBookmarksHTML(_ file: URL, source: ImportSource) throws -> BrowserSnapshot {
        let marks = try BookmarksHTMLReader.read(file)
        var snapshot = BrowserSnapshot(source: source, profileID: "export")
        snapshot.favorites = unique(marks.favorites)
        snapshot.bookmarks = marks.tree
        return snapshot
    }

    private func favoritesCount(_ source: ImportSource, marks: Result<Marks, ImportReadError>?,
                                staging: Result<ArcStaging?, ImportReadError>?) -> Result<Int, ImportReadError>? {
        let essentials = staging?.map { $0.map { mergedFavorites($0).count } ?? 0 }
        switch source {
        case .arc: return essentials
        case .zen: return marks?.map { $0.favorites.count + ((try? essentials?.get()) ?? 0) }
        default: return marks?.map { $0.favorites.count }
        }
    }

    typealias Marks = (favorites: [ImportedPage], tree: [BookmarkNode])

    private func bookmarkSet(_ source: ImportSource, _ profile: DetectedProfile) -> Result<Marks, ImportReadError>? {
        guard source != .arc, !BrowserLocations.supportedItems(source).filter({ $0 == .favorites || $0 == .bookmarks }).isEmpty else { return nil }
        return Result { try bookmarkTree(source, profile) }.mapError(asReadError)
    }

    private func spacesStaging(_ source: ImportSource, _ profile: DetectedProfile) -> Result<ArcStaging?, ImportReadError>? {
        guard source == .arc || source == .zen else { return nil }
        return Result { try spacesStagingThrowing(source, profile) }.mapError(asReadError)
    }

    private func bookmarkTree(_ source: ImportSource, _ profile: DetectedProfile) throws -> Marks {
        if source.isChromium { return try ChromiumReader.bookmarks(profile: profile.directory) }
        if source.isGecko { return try GeckoReader.bookmarks(profile: profile.directory) }
        if source == .safari { return try SafariReader.bookmarks(folder: profile.directory) }
        throw ImportReadError.unsupported("\(source.displayName) bookmarks need an HTML export.")
    }

    private func spacesStagingThrowing(_ source: ImportSource, _ profile: DetectedProfile) throws -> ArcStaging? {
        if source == .zen { return try GeckoReader.zenSpaces(profile: profile.directory, profileID: profile.id) }
        let file = BrowserLocations.arcSidebarFile(home: home)
        guard FileManager.default.fileExists(atPath: file.path) else { throw ImportReadError.unreadable }
        do { return try ArcSidebarParser.parse(ArcSourceReader.read(file).data) } catch { throw ImportReadError.unreadable }
    }

    private func historyCount(_ source: ImportSource, _ profile: DetectedProfile) throws -> Int {
        if source.isChromium { return try ChromiumReader.historyCount(profile: profile.directory) }
        if source.isGecko { return try GeckoReader.historyCount(profile: profile.directory) }
        if source == .safari { return try SafariReader.historyCount(folder: profile.directory) }
        throw ImportReadError.unreadable
    }

    private func history(_ source: ImportSource, _ profile: DetectedProfile) throws -> [ImportedHistoryEntry] {
        if source.isChromium { return try ChromiumReader.history(profile: profile.directory) }
        if source.isGecko { return try GeckoReader.history(profile: profile.directory) }
        if source == .safari { return try SafariReader.history(folder: profile.directory) }
        throw ImportReadError.unreadable
    }

    private func mergedFavorites(_ staging: ArcStaging) -> [ImportedPage] {
        unique(staging.profiles.flatMap(\.favorites).map { ImportedPage(title: $0.title, url: $0.url) })
    }

    private func unique(_ pages: [ImportedPage]) -> [ImportedPage] {
        var seen = Set<String>()
        return pages.filter { seen.insert($0.url.duplicateKey).inserted }
    }

    private func asReadError(_ error: Error) -> ImportReadError { error as? ImportReadError ?? .unreadable }

    private func availability(_ source: ImportSource, _ result: Result<Int, ImportReadError>?) -> ItemAvailability {
        switch result {
        case .success(let count): .available(count)
        case .failure(.permissionDenied): source == .safari ? .needsFullDiskAccess : .missing
        case .failure(.unsupported(let note)): .unsupported(note)
        case .failure, .none: .missing
        }
    }
}
