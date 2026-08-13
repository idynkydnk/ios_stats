import Combine
import Foundation

/// Which stats/games source the user is viewing. All data is stored in Firestore.
enum StatsSource: Equatable, Hashable {
    case myDatabase      // "My database" – this device's Firestore DB
    case other(dbId: String, displayName: String)  // Viewing another user's database (e.g. from Browse)

    var displayName: String {
        switch self {
        case .myDatabase: return "My database"
        case .other: return "Other stats"
        }
    }

    /// Name to show in page headers (e.g. "Stats (KT database)").
    func headerDisplayName(owner: DatabaseOwnerManager) -> String {
        switch self {
        case .myDatabase: return owner.myDatabaseDisplayName
        case .other(_, let displayName): return displayName
        }
    }

    /// Cloud database ID when this source is backed by Firestore.
    func cloudDbId(owner: DatabaseOwnerManager) -> String? {
        switch self {
        case .myDatabase: return owner.myDbId
        case .other(let id, _): return id
        }
    }
}
