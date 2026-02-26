import Foundation
import Combine

/// Manages edit access: owner has a share code; others can join with that code to get edit access.
/// Database sync is not implemented — this only gates add/edit UI per device.
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    private let defaults = UserDefaults.standard
    private let shareCodeKey = "stats_share_code"
    private let isOwnerKey = "stats_is_owner"
    private let enteredCodeKey = "stats_entered_code"
    
    /// This device is the database owner (created/share code lives here).
    @Published var isOwner: Bool {
        didSet { defaults.set(isOwner, forKey: isOwnerKey) }
    }
    
    /// Share code for this database (owner's code; joiners don't store this, they store enteredCode).
    @Published var shareCode: String {
        didSet { defaults.set(shareCode, forKey: shareCodeKey) }
    }
    
    /// Code this user entered to join (used to grant edit access).
    @Published var enteredCode: String? {
        didSet { defaults.set(enteredCode, forKey: enteredCodeKey) }
    }
    
    /// User can add/edit games (owner or has joined with a code).
    var canEdit: Bool {
        isOwner || (enteredCode != nil && !(enteredCode?.isEmpty ?? true))
    }
    
    private init() {
        self.isOwner = defaults.object(forKey: isOwnerKey) as? Bool ?? false
        self.shareCode = defaults.string(forKey: shareCodeKey) ?? ""
        self.enteredCode = defaults.string(forKey: enteredCodeKey)
    }
    
    private static func generateCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
    
    /// Call when owner taps "Share" to ensure they have a code (idempotent).
    func ensureOwnerCode() {
        if isOwner && (shareCode.isEmpty || shareCode.count != 6) {
            shareCode = Self.generateCode()
        }
    }
    
    /// Owner generates a new share code.
    func regenerateShareCode() {
        guard isOwner else { return }
        shareCode = Self.generateCode()
    }
    
    /// Joiner submits a code to get edit access (no server validation; we trust the code).
    func join(with code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count == 6 else { return }
        enteredCode = trimmed
    }
    
    /// Clear joined code (leave / view only).
    func leave() {
        enteredCode = nil
    }
    
    /// For owner: claim this device as owner and generate code (first-time setup).
    func claimOwner() {
        isOwner = true
        if shareCode.isEmpty {
            shareCode = Self.generateCode()
        }
    }
}
