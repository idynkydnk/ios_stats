import Foundation
import Combine
import Security
import LocalAuthentication

final class SiteAuthManager: ObservableObject {
    static let shared = SiteAuthManager()

    private let biometricKey = "com.kt.stats.pa.biometricToken"
    private let biometricEnabledKey = "com.kt.stats.pa.biometricEnabled"
    @Published private(set) var biometricEnabled = false

    var biometricName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
    }

    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private let tokenKey = "com.kt.stats.pa.token"
    private let usernameKey = "com.kt.stats.pa.username"
    private let displayNameKey = "com.kt.stats.pa.displayName"
    private let adminKey = "com.kt.stats.pa.isAdmin"

    @Published private(set) var token: String?
    @Published private(set) var username: String?
    @Published private(set) var displayName: String?
    @Published private(set) var isAdmin: Bool = false
    @Published private(set) var isPrivate: Bool = true
    @Published private(set) var needsLoginEmail = false
    @Published private(set) var sessionReady = false
    @Published private(set) var sessionRestoreError: String?
    private var attemptedAutomaticSignIn = false
    private var biometricSignInInProgress = false
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
    // Suggestions always use enabled sources, including on the Add tab.
    // Switching tabs must not change their cache key.
    var playerSuggestionsScope: String {
        let parts = [token ?? "public", username ?? "", String(isPrivate), String(isAdmin),
                     String(showStarterStats), String(statsViewRevision)]
        return String(data: try! JSONEncoder().encode(parts), encoding: .utf8)!
    }
    var accountDisplayName: String { displayName ?? username?.capitalized ?? "" }
    var needsAccountName: Bool {
        guard let username, username.hasPrefix("apple_") || username.hasPrefix("google_") else { return false }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || name == "Apple account" || name == "Google account" || name == username
    }

    private init() {
        biometricEnabled = UserDefaults.standard.bool(forKey: biometricEnabledKey)
        token = biometricEnabled ? nil : KeychainStore.get(tokenKey)
        username = UserDefaults.standard.string(forKey: usernameKey)
        displayName = UserDefaults.standard.string(forKey: displayNameKey)
        // Privileges and storage scope must be verified before showing data.
    }

    // Run once per launch, only after the app becomes active. Returning from a
    // biometric prompt or explicitly logging out must not start another prompt.
    @MainActor
    func restoreSessionOnLaunch() async {
        guard !attemptedAutomaticSignIn else { return }
        attemptedAutomaticSignIn = true
        if biometricEnabled && !isLoggedIn {
            do {
                try await loginWithBiometrics()
            } catch {
                // Leave the existing Face ID retry and email options available.
                sessionReady = true
            }
        } else {
            await refreshMe()
        }
    }

    func login(username: String, password: String, registering: Bool = false) async throws {
        let (me, token) = try await PythonAnywhereClient.shared.login(username: username, password: password, registering: registering)
        await accept(me: me, token: token)
    }

    func loginWithEmailToken(_ token: String) async throws {
        let (me, verifiedToken) = try await PythonAnywhereClient.shared.emailSession(token)
        try Task.checkCancellation()
        await accept(me: me, token: verifiedToken)
    }

    func loginWithGoogle(idToken: String) async throws {
        let (me, token) = try await PythonAnywhereClient.shared.googleLogin(idToken: idToken)
        await accept(me: me, token: token)
    }

    func loginWithApple(idToken: String, nonce: String, fullName: String? = nil) async throws {
        let (me, token) = try await PythonAnywhereClient.shared.appleLogin(idToken: idToken, nonce: nonce, fullName: fullName)
        await accept(me: me, token: token)
    }

    private func accept(me: MePayload, token: String, biometric: Bool = false) async {
        await MainActor.run {
            SiteBrowseCache.shared.invalidate()
            SiteBrowseCache.playerSuggestions.invalidate()
            SiteBrowseCache.playerDetails.invalidate()
            SiteBrowseCache.library.invalidate()
        SiteBrowseCache.navigation.invalidate()
            SiteOfflineQueue.shared.clear()
            if !biometric {
                self.removeBiometricSignIn()
                KeychainStore.set(self.tokenKey, value: token)
            }
            self.token = token
            self.username = me.username
            self.displayName = me.displayName
            UserDefaults.standard.set(me.displayName, forKey: self.displayNameKey)
            SiteOfflineQueue.shared.selectAccount(me.username)
            self.isAdmin = me.isAdmin
            self.isPrivate = me.isPrivate ?? true
            self.showStarterStats = me.showStarterStats ?? true
            self.needsLoginEmail = me.needsLoginEmail ?? false
            self.isPreviewing = false
            self.sessionReady = true
            UserDefaults.standard.set(me.username, forKey: self.usernameKey)
            UserDefaults.standard.set(me.isAdmin, forKey: self.adminKey)
            self.lastError = nil
            self.welcomeMessage = self.needsAccountName ? "Signed in" : "Signed in as \(self.accountDisplayName)"
        }
    }

    @MainActor
    func setBiometricSignIn(enabled: Bool) async throws {
        guard let token else { return }
        if enabled {
            let context = LAContext()
            context.localizedFallbackTitle = ""
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                             localizedReason: "Enable secure sign-in to Stats.")
            // Do not save credentials if the account changed during authentication.
            guard self.token == token else { throw CancellationError() }
            try KeychainStore.setBiometric(biometricKey, value: token, context: context)
            biometricEnabled = true
            UserDefaults.standard.set(true, forKey: biometricEnabledKey)
            KeychainStore.delete(tokenKey)
        } else {
            try KeychainStore.setChecked(tokenKey, value: token)
            removeBiometricSignIn()
        }
    }

    @MainActor
    func loginWithBiometrics() async throws {
        guard biometricEnabled, !isLoggedIn, !biometricSignInInProgress else { return }
        biometricSignInInProgress = true
        defer { biometricSignInInProgress = false }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        defer { context.invalidate() }
        try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                         localizedReason: "Sign in to Stats.")
        let savedToken = try KeychainStore.getBiometric(biometricKey, context: context)
        let (me, verifiedToken) = try await PythonAnywhereClient.shared.emailSession(savedToken)
        try Task.checkCancellation()
        guard biometricEnabled, !isLoggedIn else { throw CancellationError() }
        await accept(me: me, token: verifiedToken, biometric: true)
    }

    private func removeBiometricSignIn() {
        KeychainStore.delete(biometricKey)
        biometricEnabled = false
        UserDefaults.standard.removeObject(forKey: biometricEnabledKey)
    }

    @MainActor
    func refreshMe() async {
        sessionRestoreError = nil
        let refreshingToken = token
        guard isLoggedIn else {
            await MainActor.run { self.sessionReady = true }
            return
        }
        do {
            let me = try await PythonAnywhereClient.shared.me()
            guard token == refreshingToken else { return }
            guard me.loggedIn else { throw SiteAPIError.unauthorized }
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
                self.needsLoginEmail = me.needsLoginEmail ?? false
                if !self.sessionReady { self.isPreviewing = false }
                self.sessionReady = true
                UserDefaults.standard.set(me.username, forKey: self.usernameKey)
                UserDefaults.standard.set(me.isAdmin, forKey: self.adminKey)
            }
        } catch {
            await MainActor.run {
                guard self.token == refreshingToken else { return }
                switch error {
                case SiteAPIError.unauthorized, SiteAPIError.http(401, _):
                    self.clearSession()
                    self.lastError = error.localizedDescription
                default:
                    // A connection failure is not a sign-out. Keep credentials,
                    // and keep unverified account data behind the launch screen.
                    if !self.sessionReady {
                        self.sessionRestoreError = "Couldn’t connect to Stats. Your sign-in is saved. Try again when you’re connected."
                    }
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func logout() async {
        // Face ID keeps the server credential only in the protected Keychain item.
        // Revoking it here would make the next biometric sign-in impossible.
        if biometricEnabled {
            clearSession(preservingBiometrics: true)
        } else {
            try? await PythonAnywhereClient.shared.logout()
            clearSession()
        }
    }

    private func clearSession(preservingBiometrics: Bool = false) {
        SiteBrowseCache.shared.invalidate()
        SiteBrowseCache.playerSuggestions.invalidate()
        SiteBrowseCache.playerDetails.invalidate()
        SiteBrowseCache.library.invalidate()
        SiteBrowseCache.navigation.invalidate()
        SiteOfflineQueue.shared.clear()
        URLCache.shared.removeAllCachedResponses()
        KeychainStore.delete(tokenKey)
        if !preservingBiometrics { removeBiometricSignIn() }
        token = nil
        username = nil
        displayName = nil
        isAdmin = false
        isPrivate = true
        showStarterStats = true
        needsLoginEmail = false
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
            statsSourcesChanged()
        }
    }

    func statsSourcesChanged() {
        SiteBrowseCache.shared.invalidate()
        SiteBrowseCache.playerSuggestions.invalidate()
        SiteBrowseCache.playerDetails.invalidate()
        SiteBrowseCache.library.invalidate()
        SiteBrowseCache.navigation.invalidate()
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
            UserDefaults.standard.removeObject(forKey: "com.kt.stats.pa.lastLoginEmail")
            clearSession()
        }
    }
}

enum KeychainStore {
    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw SiteAPIError.message("Couldn’t access your saved sign-in. Try again, or sign in with email.")
        }
    }

    static func setChecked(_ key: String, value: String) throws {
        delete(key)
        try check(SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: Data(value.utf8)
        ] as CFDictionary, nil))
    }

    static func setBiometric(_ key: String, value: String, context: LAContext) throws {
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil) else {
            throw SiteAPIError.message("Set up Face ID or Touch ID in Settings first.")
        }
        delete(key)
        try check(SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrAccessControl: access,
            kSecUseAuthenticationContext: context,
            kSecValueData: Data(value.utf8)
        ] as CFDictionary, nil))
    }

    static func getBiometric(_ key: String, context: LAContext) throws -> String {
        var result: AnyObject?
        try check(SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecUseAuthenticationContext: context,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result))
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw SiteAPIError.message("Please sign in with email again.")
        }
        return token
    }

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
