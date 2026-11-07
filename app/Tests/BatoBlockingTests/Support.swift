import Foundation
@testable import BatoBlocking

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bato-blocking-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class FakeFetcher: FilterListFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: [Result<FetchResult, Error>]] = [:]
    private(set) var requests: [(url: URL, etag: String?)] = []

    func enqueue(_ url: URL, _ result: Result<FetchResult, Error>) {
        lock.withLock { responses[url, default: []].append(result) }
    }

    func fetch(_ url: URL, etag: String?, maximumBytes: Int) async throws -> FetchResult {
        let next = lock.withLock { () -> Result<FetchResult, Error>? in
            requests.append((url, etag))
            return responses[url]?.isEmpty == false ? responses[url]!.removeFirst() : nil
        }
        return try (next ?? .failure(URLError(.notConnectedToInternet))).get()
    }
}

func listData(rules: Int, header: String = "[Adblock Plus 2.0]") -> Data {
    let body = (0..<rules).map { "||ads\($0).example^" }.joined(separator: "\n")
    return Data("\(header)\n! Title: Fake\n\(body)\n".utf8)
}

let fakeSource = FilterListSource(id: "fake", url: URL(string: "https://lists.invalid/fake.txt")!,
                                  minimumRuleCount: 5, maximumBytes: 10_000)
