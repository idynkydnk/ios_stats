import Combine
import Foundation

/// Manages this device's cloud database (myDbId), which databases we can edit (editableDbIds), upload, and code create/enter.
final class DatabaseOwnerManager: ObservableObject {
    static let shared = DatabaseOwnerManager()

    private let keychainService = "com.kt.stats.dbowner"
    private let myDbIdKey = "my_db_id"
    private let editableDbIdsKey = "editable_db_ids"
    private let displayNameKey = "com.kt.stats.my_db_display_name"

    /// This device's database ID (created on first upload). Nil until user uploads.
    @Published private(set) var myDbId: String? {
        didSet { saveMyDbId(myDbId) }
    }

    /// Database IDs this device can edit (myDbId + any from entered codes).
    @Published private(set) var editableDbIds: Set<String> = [] {
        didSet { saveEditableDbIds(editableDbIds) }
    }

    /// Display name for "My database" (stored in UserDefaults).
    var myDatabaseDisplayName: String {
        get { UserDefaults.standard.string(forKey: displayNameKey) ?? "My database" }
        set { UserDefaults.standard.set(newValue, forKey: displayNameKey) }
    }

    /// True when signed in and this user's id is in Supabase config admin_uids.
    @Published private(set) var isAdmin: Bool = false

    private init() {
        self.myDbId = Self.loadMyDbId()
        self.editableDbIds = Self.loadEditableDbIds()
        refreshAdminStatus()
    }

    /// Call when myDbId or auth state may have changed. Admin only when signed in with Google AND uid is in config admin_uids. No fallback when signed out.
    func refreshAdminStatus() {
        guard let uid = AuthManager.shared.uid else {
            isAdmin = false
            return
        }
        let uidLower = uid.lowercased()
        cloud.fetchAdminUIDs { [weak self] result in
            switch result {
            case .success(let uids):
                // Compare case-insensitively; Supabase often stores UUIDs lowercase.
                self?.isAdmin = uids.contains { $0.lowercased() == uidLower }
            case .failure:
                self?.isAdmin = false
            }
        }
    }

    // MARK: - Persistence

    private static func loadMyDbId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kt.stats.dbowner",
            kSecAttrAccount as String: "my_db_id",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    private func saveMyDbId(_ value: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: myDbIdKey
        ]
        SecItemDelete(query as CFDictionary)
        if let value = value, let data = value.data(using: .utf8) {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func loadEditableDbIds() -> Set<String> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kt.stats.dbowner",
            kSecAttrAccount as String: "editable_db_ids",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(decoded)
    }

    private func saveEditableDbIds(_ value: Set<String>) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: editableDbIdsKey
        ]
        SecItemDelete(query as CFDictionary)
        if !value.isEmpty, let data = try? JSONEncoder().encode(Array(value)) {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    // MARK: - Permissions

    /// True for this device's own database, any database unlocked via a share code, or any database when signed in as admin (admin can view and edit everything).
    func canEdit(dbId: String) -> Bool {
        if isAdmin { return true }
        return myDbId == dbId || editableDbIds.contains(dbId)
    }

    /// True if this device has uploaded and has a cloud database.
    var hasMyDatabase: Bool { myDbId != nil }

    // MARK: - Upload

    /// Create or update this device's cloud database. If no database exists yet, displayName is required and must be unique.
    func uploadLocalToMyDatabase(displayName: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let gamesToUpload: [LegacyGame] = []
        if let existingId = myDbId {
            cloud.ensureDatabase(dbId: existingId, displayName: myDatabaseDisplayName) { [weak self] result in
                switch result {
                case .failure(let err):
                    DispatchQueue.main.async { completion(.failure(err)) }
                case .success:
                    self?.uploadGames(gamesToUpload, to: existingId, index: 0, completion: completion)
                }
            }
            return
        }
        guard let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            completion(.failure(NSError(domain: "DatabaseOwnerManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please enter a name for your database."])))
            return
        }
        cloud.reserveDatabaseName(displayName: name) { [weak self] result in
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let dbId):
                self?.myDbId = dbId
                self?.myDatabaseDisplayName = name
                self?.editableDbIds.insert(dbId)
                self?.refreshAdminStatus()
                self?.uploadGames(gamesToUpload, to: dbId, index: 0, completion: completion)
            }
        }
    }

    private func uploadGames(_ games: [LegacyGame], to dbId: String, index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        if index >= games.count {
            DispatchQueue.main.async { completion(.success(())) }
            return
        }
        let g = games[index]
        cloud.insertGame(dbId: dbId, winner1: g.winner1, winner2: g.winner2, winnerScore: g.winnerScore, loser1: g.loser1, loser2: g.loser2, loserScore: g.loserScore, comment: g.comment, editorDbId: dbId) { [weak self] result in
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success:
                self?.uploadGames(games, to: dbId, index: index + 1, completion: completion)
            }
        }
    }

    // MARK: - Rename / Delete (owner only)

    /// Rename this device's cloud database. Fails if no database or name is taken.
    func renameMyDatabase(newDisplayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let dbId = myDbId else {
            completion(.failure(NSError(domain: "DatabaseOwnerManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "You don't have a cloud database to rename."])))
            return
        }
        cloud.renameDatabase(dbId: dbId, currentDisplayName: myDatabaseDisplayName, newDisplayName: newDisplayName) { [weak self] result in
            switch result {
            case .success:
                self?.myDatabaseDisplayName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }

    /// Delete this device's cloud database and clear local state. Irreversible.
    func deleteMyDatabase(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let dbId = myDbId else {
            completion(.failure(NSError(domain: "DatabaseOwnerManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "You don't have a cloud database to delete."])))
            return
        }
        let displayName = myDatabaseDisplayName
        cloud.deleteDatabase(dbId: dbId, displayName: displayName) { [weak self] result in
            switch result {
            case .success:
                self?.myDbId = nil
                var updated = self?.editableDbIds ?? []
                updated.remove(dbId)
                self?.editableDbIds = updated
                self?.myDatabaseDisplayName = "My database"
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }

    // MARK: - Codes

    /// Create a shareable code that grants edit access to this device's database. Multiple devices can use the same code.
    func createCode(completion: @escaping (Result<String, Error>) -> Void) {
        guard let dbId = myDbId else {
            completion(.failure(NSError(domain: "DatabaseOwnerManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Upload your stats first to create a code."])))
            return
        }
        cloud.createCode(dbId: dbId, completion: completion)
    }

    /// Enter a code; on success adds the code's dbId to editableDbIds. The code stays valid for other devices.
    func enterCode(_ code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        cloud.getCodeDbId(code: code) { [weak self] result in
            switch result {
            case .success(let dbId):
                self?.editableDbIds.insert(dbId)
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }
}
