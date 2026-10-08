import Foundation
import Combine
import Security

final class SiteAuthManager: ObservableObject {
    static let shared = SiteAuthManager()

    private let tokenKey = "com.kt.stats.pa.token"
    private let usernameKey = "com.kt.stats.pa.username"
    private let displayNameKey = "com.kt.stats.pa.displayName"
    private let adminKey = "com.kt.stats.pa.isAdmin"

    @Published private(set) var token: String?
    @Published private(set) var username: String?
    @Published private(set) var displayName: String?
    @Published private(set) var isAdmin: Bool = false
    @Published private(set) var isPrivate: Bool = true
    @Published private(set) var sessionReady = false
    @Published private(set) var showStarterStats = true
    @Published var isPreviewing = true
    @Published var browseSelectedStats = true
    @Published private(set) var statsViewRevision = 0
    @Published var lastError: String?
    @Published private(set) var welcomeMessage: String?

    // Include the session and every browsing scope; raw credentials never go to disk.
    var browseCacheScope: String {
        let parts = [token ?? "public", username ?? "", String(isPrivate), String(isAdmin),
                     String(isPreviewing), String(browseSelectedStats), String(showStarterStats)]
        return String(data: try! JSONEncoder().encode(parts), encoding: .utf8)!
    }

    var isLoggedIn: Bool { token != nil && !(token?.isEmpty ?? true) }
    var accountDisplayName: String { displayName ?? username?.capitalized ?? "" }
    var needsAccountName: Bool {
        guard let username, username.hasPrefix("apple_") || username.hasPrefix("google_") else { return false }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || name == "Apple account" || name == "Google account" || name == username
    }

    private init() {
        token = KeychainStore.get(tokenKey)
        username = UserDefaults.standard.string(forKey: usernameKey)
        displayName = UserDefaults.standard.string(forKey: displayNameKey)
        // Privileges and storage scope must be verified before showing data.
    }

    func login(username: String, password: String, registering: Bool = false) async throws {
        let (me, token) = try await PythonAnywhereClient.shared.login(username: username, password: password, registering: registering)
        await accept(me: me, token: token)
    }

    func loginWithGoogle(idToken: String) async throws {
        let (me, token) = try await PythonAnywhereClient.shared.googleLogin(idToken: idToken)
        await accept(me: me, token: token)
    }

    func loginWithApple(idToken: String, nonce: String, fullName: String? = nil) async throws {
        let (me, token) = try await PythonAnywhereClient.shared.appleLogin(idToken: idToken, nonce: nonce, fullName: fullName)
        await accept(me: me, token: token)
    }

    private func accept(me: MePayload, token: String) async {
        await MainActor.run {
            SiteBrowseCache.shared.invalidate()
            SiteOfflineQueue.shared.clear()
            KeychainStore.set(self.tokenKey, value: token)
            self.token = token
            self.username = me.username
            self.displayName = me.displayName
            UserDefaults.standard.set(me.displayName, forKey: self.displayNameKey)
            SiteOfflineQueue.shared.selectAccount(me.username)
            self.isAdmin = me.isAdmin
            self.isPrivate = me.isPrivate ?? true
            self.showStarterStats = me.showStarterStats ?? true
            self.isPreviewing = false
            self.sessionReady = true
            UserDefaults.standard.set(me.username, forKey: self.usernameKey)
            UserDefaults.standard.set(me.isAdmin, forKey: self.adminKey)
            self.lastError = nil
            self.welcomeMessage = self.needsAccountName ? "Signed in" : "Signed in as \(self.accountDisplayName)"
        }
    }

    func refreshMe() async {
        guard isLoggedIn else {
            await MainActor.run { self.sessionReady = true }
            return
        }
        do {
            let me = try await PythonAnywhereClient.shared.me()
            guard me.isPrivate != nil else {
                throw SiteAPIError.message("The server needs the accounts update before you can sign in.")
            }
            await MainActor.run {
                self.username = me.username
                self.displayName = me.displayName
                UserDefaults.standard.set(me.displayName, forKey: self.displayNameKey)
                SiteOfflineQueue.shared.selectAccount(me.username)
                self.isAdmin = me.isAdmin
                self.isPrivate = me.isPrivate ?? true
                self.showStarterStats = me.showStarterStats ?? true
                if !self.sessionReady { self.isPreviewing = false }
                self.sessionReady = true
                UserDefaults.standard.set(me.username, forKey: self.usernameKey)
                UserDefaults.standard.set(me.isAdmin, forKey: self.adminKey)
            }
        } catch {
            await MainActor.run {
                self.clearSession()
                self.lastError = error.localizedDescription
            }
        }
    }

    func logout() async {
        try? await PythonAnywhereClient.shared.logout()
        await MainActor.run { clearSession() }
    }

    private func clearSession() {
        SiteBrowseCache.shared.invalidate()
        SiteOfflineQueue.shared.clear()
        URLCache.shared.removeAllCachedResponses()
        KeychainStore.delete(tokenKey)
        token = nil
        username = nil
        displayName = nil
        isAdmin = false
        isPrivate = true
        showStarterStats = true
        isPreviewing = true
        sessionReady = true
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        UserDefaults.standard.removeObject(forKey: adminKey)
        welcomeMessage = nil
    }

    func clearWelcome() {
        welcomeMessage = nil
    }

    func setStarterStats(visible: Bool) async throws {
        try await PythonAnywhereClient.shared.setStarterStats(visible: visible)
        await MainActor.run {
            showStarterStats = visible
            statsViewRevision += 1
        }
    }

    func statsSourcesChanged() {
        SiteBrowseCache.shared.invalidate()
        statsViewRevision += 1
    }

    @MainActor
    func setDisplayName(_ name: String) async throws {
        let accountToken = token
        let wasMissingName = needsAccountName
        let savedName = try await PythonAnywhereClient.shared.setDisplayName(name)
        guard token == accountToken, isLoggedIn else { return }
        displayName = savedName
        UserDefaults.standard.set(savedName, forKey: displayNameKey)
        if wasMissingName || welcomeMessage != nil { welcomeMessage = "Signed in as \(savedName)" }
    }

    func deleteAccount() async throws {
        try await PythonAnywhereClient.shared.deleteAccount()
        await MainActor.run {
            if let username { SiteOfflineQueue.shared.removeAccount(username) }
            clearSession()
        }
    }
}

enum KeychainStore {
    static func set(_ key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
