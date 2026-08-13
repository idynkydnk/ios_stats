import Combine
import Foundation

/// Manages editor access: who can add/edit games. Access is granted by entering a valid code.
/// Codes are validated and consumed via the cloud backend (Supabase).
final class EditorAccessManager: ObservableObject {
    static let shared = EditorAccessManager()

    private let keychainService = "com.kt.stats.editor"
    private let keychainAccount = "has_edit_access"

    @Published private(set) var hasEditAccess: Bool {
        didSet { saveHasEditAccess(hasEditAccess) }
    }

    private init() {
        self.hasEditAccess = Self.loadHasEditAccess()
    }

    private static func loadHasEditAccess() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kt.stats.editor",
            kSecAttrAccount as String: "has_edit_access",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            return false
        }
        return string == "1"
    }

    private func saveHasEditAccess(_ value: Bool) {
        let data = (value ? "1" : "0").data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        if value {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    /// Validates the code and grants edit access on this device if valid. Uses cloud backend.
    func enterCode(_ code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async { completion(.failure(EditorAccessError.emptyCode)) }
            return
        }
        cloud.getCodeDbId(code: trimmed) { [weak self] result in
            switch result {
            case .success:
                self?.hasEditAccess = true
                DispatchQueue.main.async { completion(.success(())) }
            case .failure:
                DispatchQueue.main.async { completion(.failure(EditorAccessError.invalidCode)) }
            }
        }
    }

    /// Creates a shareable code for the given database. Caller must pass dbId (e.g. from DatabaseOwnerManager.myDbId).
    func createCode(dbId: String, completion: @escaping (Result<String, Error>) -> Void) {
        cloud.createCode(dbId: dbId, completion: completion)
    }

    func revokeAccess() {
        hasEditAccess = false
    }
}

enum EditorAccessError: LocalizedError {
    case emptyCode
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .emptyCode: return "Please enter a code."
        case .invalidCode: return "Invalid or expired code."
        }
    }
}
