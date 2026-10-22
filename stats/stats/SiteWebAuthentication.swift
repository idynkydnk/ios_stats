import Foundation

/// Credentials are attached only to the exact HTTPS origin owned by this app.
/// Other links open externally, without carrying the app's authorization header.
nonisolated enum SiteWebAuthentication {
    static func isSameOrigin(_ url: URL, as baseURL: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && baseURL.scheme?.lowercased() == "https"
            && url.host?.lowercased() == baseURL.host?.lowercased()
            && (url.port ?? 443) == (baseURL.port ?? 443)
    }

    static func request(_ url: URL, baseURL: URL, token: String?) -> URLRequest {
        request(URLRequest(url: url), baseURL: baseURL, token: token)
    }

    static func request(_ source: URLRequest, baseURL: URL, token: String?) -> URLRequest {
        var request = source
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        if let url = source.url, isSameOrigin(url, as: baseURL), let token, !token.isEmpty {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

/// WebKit requires every JavaScript confirmation callback to finish exactly once,
/// including when presentation is cancelled or the reader is released.
nonisolated final class SiteWebConfirmation {
    private let lock = NSLock()
    private var completion: ((Bool) -> Void)?

    init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }

    func finish(_ accepted: Bool) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(accepted)
    }

    deinit { finish(false) }
}
