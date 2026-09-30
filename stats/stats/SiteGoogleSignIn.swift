import AuthenticationServices
import CryptoKit
import UIKit
import Combine

@MainActor
final class SiteGoogleSignIn: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?

    func signIn() async throws {
        let clientID = try await PythonAnywhereClient.shared.googleClientID()
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else {
            throw SiteAPIError.message("Google sign-in has not been configured yet. You can create an account with a username and password.")
        }
        let scheme = "com.googleusercontent.apps." + clientID.dropLast(suffix.count)
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard schemes.contains(scheme) else {
            throw SiteAPIError.message("Google sign-in needs to be enabled in this app build. You can create an account with a username and password.")
        }
        anchor = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        guard anchor != nil else { throw SiteAPIError.message("Please try signing in again.") }
        let verifier = randomValue()
        let state = randomValue()
        let redirect = scheme + ":/oauthredirect"
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var authorization = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        authorization.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorization.url!, callbackURLScheme: scheme) { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: SiteAPIError.message("Google sign-in did not finish.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session
            if !session.start() {
                continuation.resume(throwing: SiteAPIError.message("Could not open Google sign-in."))
            }
        }
        defer { webSession = nil; anchor = nil }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SiteAPIError.message("Google sign-in could not be verified. Please try again.")
        }
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        struct Tokens: Decodable { var id_token: String }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let tokens = try? JSONDecoder().decode(Tokens.self, from: data) else {
            throw SiteAPIError.message("Google sign-in did not finish. Please try again.")
        }
        try await SiteAuthManager.shared.loginWithGoogle(idToken: tokens.id_token)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor!
    }

    private func randomValue() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
