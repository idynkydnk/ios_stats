import Foundation
import Combine
import Security

final class SiteAuthManager: ObservableObject {
    static let shared = SiteAuthManager()

    private let tokenKey = "com.kt.stats.pa.token"
    private let usernameKey = "com.kt.stats.pa.username"
    private let adminKey = "com.kt.stats.pa.isAdmin"

    @Published private(set) var token: String?
    @Published private(set) var username: String?
    @Published private(set) var isAdmin: Bool = false
    @Published var lastError: String?

    var isLoggedIn: Bool { token != nil && !(token?.isEmpty ?? true) }

    private init() {
        token = KeychainStore.get(tokenKey)
        username = UserDefaults.standard.string(forKey: usernameKey)
        isAdmin = UserDefaults.standard.bool(forKey: adminKey)
    }

    func login(username: String, password: String) async throws {
        let me = try await PythonAnywhereClient.shared.login(username: username, password: password)
        await MainActor.run {
            self.token = KeychainStore.get(self.tokenKey)
            self.username = me.username
            self.isAdmin = me.isAdmin
            UserDefaults.standard.set(me.username, forKey: self.usernameKey)
            UserDefaults.standard.set(me.isAdmin, forKey: self.adminKey)
            self.lastError = nil
        }
    }

    func refreshMe() async {
        guard isLoggedIn else { return }
        do {
            let me = try await PythonAnywhereClient.shared.me()
            await MainActor.run {
                self.username = me.username
                self.isAdmin = me.isAdmin
                UserDefaults.standard.set(me.username, forKey: self.usernameKey)
                UserDefaults.standard.set(me.isAdmin, forKey: self.adminKey)
            }
        } catch {
            if case SiteAPIError.unauthorized = error {
                await MainActor.run { self.clearSession() }
            }
        }
    }

    func logout() async {
        try? await PythonAnywhereClient.shared.logout()
        await MainActor.run { clearSession() }
    }

    func storeToken(_ token: String, username: String) {
        KeychainStore.set(tokenKey, value: token)
        if Thread.isMainThread {
            self.token = token
            self.username = username
            UserDefaults.standard.set(username, forKey: usernameKey)
        } else {
            DispatchQueue.main.async {
                self.token = token
                self.username = username
                UserDefaults.standard.set(username, forKey: self.usernameKey)
            }
        }
    }

    private func clearSession() {
        KeychainStore.delete(tokenKey)
        token = nil
        username = nil
        isAdmin = false
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: adminKey)
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
