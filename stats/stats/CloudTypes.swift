import Foundation

/// Shared activity log entry (used by both Firebase and Supabase backends).
struct ActivityEntry: Identifiable {
    let id: String
    let action: String
    let at: Date
    let editorDbId: String
    let gameId: String?
    let summary: String?
}

/// Player row for admin view/edit. docId is the normalized key; displayName is what appears in games/UI.
struct AdminPlayerRow: Identifiable {
    let docId: String
    var displayName: String
    var firstName: String?
    var lastName: String?
    var id: String { docId }
}
