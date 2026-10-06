import SwiftUI
import AuthenticationServices
import CryptoKit

struct SiteAppleSignInButton: View {
    @Binding var busy: Bool
    @Binding var error: String?
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce: String?
    @State private var challengeFailed = false

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            busy = true
            error = nil
            request.requestedScopes = [.fullName, .email]
            request.nonce = SHA256.hash(data: Data((nonce ?? "").utf8))
                .map { String(format: "%02x", $0) }.joined()
        } onCompletion: { result in
            Task {
                defer { busy = false }
                do {
                    let authorization = try result.get()
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let token = String(data: tokenData, encoding: .utf8),
                          let nonce else {
                        throw SiteAPIError.message("Apple sign-in did not finish. Please try again.")
                    }
                    // Apple may only provide the name once. Keep it for a retry
                    // if the network or our server interrupts this sign-in.
                    let nameKey = "com.kt.stats.apple.fullName.\(credential.user)"
                    if let components = credential.fullName {
                        let name = PersonNameComponentsFormatter().string(from: components)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { KeychainStore.set(nameKey, value: name) }
                    }
                    try await SiteAuthManager.shared.loginWithApple(
                        idToken: token, nonce: nonce, fullName: KeychainStore.get(nameKey))
                    KeychainStore.delete(nameKey)
                } catch {
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        self.error = error.localizedDescription
                    }
                    await loadChallenge()
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 48)
        .disabled(busy || nonce == nil)
        .task { await loadChallenge() }
        if challengeFailed {
            Button("Retry Apple sign-in") { Task { await loadChallenge() } }
                .disabled(busy)
        }
    }

    private func loadChallenge() async {
        nonce = nil
        challengeFailed = false
        do { nonce = try await PythonAnywhereClient.shared.appleChallenge() }
        catch { challengeFailed = true }
    }
}
