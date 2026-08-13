import Combine
import Foundation
import GoogleSignIn
import Supabase
import UIKit

/// Manages sign-in state via Supabase Auth. Uses Google Sign-In to get an ID token, then signs in to Supabase.
/// Admin is determined by signed-in user id (config admin_uids in Supabase).
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    /// Lightweight user info for display. Nil when signed out.
    struct AuthUser {
        var id: String
        var email: String?
        var displayName: String?
    }

    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var userEmail: String?

    private var client: SupabaseClient?
    private var authTask: Task<Void, Never>?

    private init() {
        loadSupabaseAndListen()
    }

    private func loadSupabaseAndListen() {
        guard let url = Bundle.main.url(forResource: "Supabase-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let base = dict["SUPABASE_URL"] as? String,
              let key = dict["SUPABASE_ANON_KEY"] as? String,
              let supabaseURL = URL(string: base), !key.isEmpty else {
            return
        }
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: key)
        Task { @MainActor in
            if let session = try? await client?.auth.session {
                updateFromSession(session)
            } else {
                currentUser = nil
                userEmail = nil
            }
        }
        authTask = Task { [weak self] in
            guard let self = self, let client = self.client else { return }
            for await (_, session) in client.auth.authStateChanges {
                await MainActor.run {
                    self.updateFromSession(session)
                }
            }
        }
    }

    private func updateFromSession(_ session: Session?) {
        guard let session = session else {
            currentUser = nil
            userEmail = nil
            DispatchQueue.main.async { DatabaseOwnerManager.shared.refreshAdminStatus() }
            return
        }
        let u = session.user
        let name = Self.stringFromMetadata(u.userMetadata["full_name"] as Any?) ?? Self.stringFromMetadata(u.userMetadata["name"] as Any?)
        currentUser = AuthUser(
            id: u.id.uuidString,
            email: u.email,
            displayName: name
        )
        userEmail = u.email
        // Refresh admin status whenever session updates (e.g. right after sign-in) so Admin section appears.
        DispatchQueue.main.async {
            DatabaseOwnerManager.shared.refreshAdminStatus()
        }
    }

    /// Safely get a string from Supabase user metadata (values may be AnyJSON, not String).
    private static func stringFromMetadata(_ value: Any?) -> String? {
        guard let value = value else { return nil }
        if let s = value as? String { return s }
        let desc = (value as? CustomStringConvertible)?.description ?? ""
        return desc.isEmpty || desc.hasPrefix("Optional(") ? nil : desc
    }

    var isSignedIn: Bool { currentUser != nil }
    var uid: String? { currentUser?.id }

    /// Sign in with Google: get ID token from Google, then sign in to Supabase with it. Must run on main thread for UI.
    func signInWithGoogle(completion: @escaping (Result<Void, Error>) -> Void) {
        func doSignIn() {
        guard let client = client else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Supabase not configured. Check Supabase-Info.plist."]))) }
            return
        }
        let rootVC: UIViewController? = {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.compactMap { $0 as? UIWindowScene }.first
            let keyWindow = windowScene?.windows.first { $0.isKeyWindow }
            return keyWindow?.rootViewController ?? windowScene?.windows.first?.rootViewController
        }()
        guard let rootVC = rootVC else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "No window to present sign-in."]))) }
            return
        }
        let clientID: String? = {
            if let url = Bundle.main.url(forResource: "Supabase-Info", withExtension: "plist"),
               let dict = NSDictionary(contentsOf: url) as? [String: Any],
               let id = dict["GOOGLE_CLIENT_ID"] as? String, !id.isEmpty { return id }
            return Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        }()
        guard let clientID = clientID, !clientID.isEmpty else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing GOOGLE_CLIENT_ID in Supabase-Info.plist or Info.plist."]))) }
            return
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "No ID token."]))) }
                return
            }
            let accessTokenStr = user.accessToken.tokenString
            Task {
                do {
                    _ = try await client.auth.signInWithIdToken(
                        credentials: OpenIDConnectCredentials(
                            provider: .google,
                            idToken: idToken,
                            accessToken: accessTokenStr
                        )
                    )
                    await MainActor.run { completion(.success(())) }
                } catch {
                    await MainActor.run { completion(.failure(error)) }
                }
            }
        }
        }
        if Thread.isMainThread {
            doSignIn()
        } else {
            DispatchQueue.main.async { doSignIn() }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        Task {
            try? await client?.auth.signOut()
            await MainActor.run {
                currentUser = nil
                userEmail = nil
            }
        }
    }

    static func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
