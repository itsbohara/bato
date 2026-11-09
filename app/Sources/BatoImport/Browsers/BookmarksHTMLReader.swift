import Foundation

/// The Netscape bookmarks HTML every browser exports. Used for Orion, whose own data format is not
/// documented, and for any browser the user prefers to export from. The toolbar folder (marked
/// `PERSONAL_TOOLBAR_FOLDER`) becomes Favorites.
enum BookmarksHTMLReader {
    static let maxBytes = 64 * 1024 * 1024

    static func read(_ url: URL) throws -> (favorites: [ImportedPage], tree: [BookmarkNode]) {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxBytes,
              let data = try? Data(contentsOf: url) else { throw ImportReadError.unreadable }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ html: String) -> (favorites: [ImportedPage], tree: [BookmarkNode]) {
        struct Level {
            var name: String
            var isToolbar: Bool
            var nodes: [BookmarkNode] = []
        }
        var stack = [Level(name: "", isToolbar: false)]
        var pending: Level?
        var favorites: [ImportedPage] = []
        let tag = try! NSRegularExpression(pattern: #"<(/?)(DL|H3|A)\b([^>]*)>([^<]*)"#, options: .caseInsensitive)
        let nsHTML = html as NSString
        for match in tag.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let closing = nsHTML.substring(with: match.range(at: 1)) == "/"
            let name = nsHTML.substring(with: match.range(at: 2)).uppercased()
            let attributes = nsHTML.substring(with: match.range(at: 3))
            let text = decode(nsHTML.substring(with: match.range(at: 4)))
            switch (name, closing) {
            case ("H3", false):
                pending = Level(name: text, isToolbar: attributes.uppercased().contains("PERSONAL_TOOLBAR_FOLDER=\"TRUE\""))
            case ("DL", false):
                if let level = pending {
                    stack.append(level)
                    pending = nil
                }
            case ("DL", true):
                guard stack.count > 1 else { continue }
                let level = stack.removeLast()
                if level.isToolbar {
                    for node in level.nodes {
                        if case .page(let page) = node { favorites.append(page) } else { stack[stack.count - 1].nodes.append(node) }
                    }
                } else if !level.nodes.isEmpty {
                    stack[stack.count - 1].nodes.append(.folder(name: level.name, children: level.nodes))
                }
            case ("A", false):
                guard let href = attribute("HREF", in: attributes), let link = URL(string: decode(href)), link.isWebURL else { continue }
                stack[stack.count - 1].nodes.append(.page(ImportedPage(title: text, url: link)))
            default: break
            }
        }
        while stack.count > 1 {
            let level = stack.removeLast()
            if !level.nodes.isEmpty { stack[stack.count - 1].nodes.append(.folder(name: level.name, children: level.nodes)) }
        }
        return (favorites, stack[0].nodes)
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        guard let range = attributes.range(of: "\(name)=\"", options: .caseInsensitive),
              let end = attributes[range.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(attributes[range.upperBound..<end])
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
