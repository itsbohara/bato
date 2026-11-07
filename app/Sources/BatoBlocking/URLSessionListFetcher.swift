import Foundation

/// Conditional HTTPS GET with a hard size cap. Sends no cookies and no identifiers.
public struct URLSessionListFetcher: FilterListFetching {
    public enum FetchError: Error, LocalizedError {
        case insecureURL
        case httpStatus(Int)
        case tooLarge

        public var errorDescription: String? {
            switch self {
            case .insecureURL: "List URL is not HTTPS."
            case let .httpStatus(code): "List server answered HTTP \(code)."
            case .tooLarge: "List download exceeded the size limit."
            }
        }
    }

    public init() {}

    public func fetch(_ url: URL, etag: String?, maximumBytes: Int) async throws -> FetchResult {
        guard url.scheme == "https" else { throw FetchError.insecureURL }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        var request = URLRequest(url: url)
        request.setValue("Bato", forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await URLSession(configuration: configuration).bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.httpStatus(0) }
        if http.statusCode == 304 { return .notModified }
        guard http.statusCode == 200 else { throw FetchError.httpStatus(http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumBytes { throw FetchError.tooLarge }
        }
        return .content(data, etag: http.value(forHTTPHeaderField: "ETag"))
    }
}
