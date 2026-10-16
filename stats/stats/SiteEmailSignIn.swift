import Foundation
import Combine

/// Each sign-in owns an in-memory cookie jar. The rest of the app continues to
/// authenticate only with its verified Keychain bearer token.
@MainActor
final class SiteEmailSignIn: ObservableObject {
    enum Step: String, Decodable { case email, code, signup, complete }
    struct Response: Decodable {
        var step: Step?
        var csrf: String?
        var email: String?
        var enrolling: Bool?
        var token: String?
        var error: String?
    }
    enum LoginError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let message): return message }
        }
    }

    @Published private(set) var state: Response?
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = true
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration)
        }
    }

    deinit { session.invalidateAndCancel() }

    func request(_ fields: [String: String]? = nil, bearer: String? = nil) async throws -> String? {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/auth/email"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if var fields {
            guard let csrf = state?.csrf else {
                throw LoginError.message("Please reopen sign-in and try again.")
            }
            fields["csrf"] = csrf
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(fields)
        } else {
            request.httpMethod = "GET"
            if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw LoginError.message("Couldn’t reach Stats. Please try again.")
        }
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LoginError.message("Email sign-in is temporarily unavailable. Please try again later.")
        }
        if payload.step != nil { state = payload }
        guard (200..<300).contains(http.statusCode), let step = payload.step else {
            throw LoginError.message(payload.error ?? "Couldn’t sign in. Please try again.")
        }
        if step == .complete {
            guard let token = payload.token, !token.isEmpty else {
                throw LoginError.message("Sign-in did not finish. Please try again.")
            }
            return token
        }
        guard payload.csrf != nil else {
            throw LoginError.message("Please reopen sign-in and try again.")
        }
        return nil
    }
}
