import Foundation

/// Single entry point for cloud backend. App uses Supabase only.
var cloud: CloudBackendProtocol {
    SupabaseManager.shared
}

/// Protocol for the cloud backend (Supabase). Used by the app for all database and auth-related cloud operations.
protocol CloudBackendProtocol: AnyObject {
    func cachedPlayers(dbId: String, editorDbId: String?) -> [PlayerInfo]?
    func prefetchPlayers(dbId: String, editorDbId: String?)
    func fetchGames(dbId: String, limit: Int?, completion: @escaping (Result<[LegacyGame], Error>) -> Void)
    func loadMoreGames(dbId: String, limit: Int, completion: @escaping (Result<[LegacyGame], Error>) -> Void)
    func hasMoreGames(dbId: String) -> Bool
    func insertGame(dbId: String, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, comment: String, editorDbId: String?, completion: @escaping (Result<Void, Error>) -> Void)
    func insertGame(dbId: String, date: Date, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, comment: String, editorDbId: String?, completion: @escaping (Result<String, Error>) -> Void)
    func updateGame(dbId: String, documentId: String, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, comment: String, editorDbId: String?, completion: @escaping (Result<Void, Error>) -> Void)
    func deleteGame(dbId: String, documentId: String, editorDbId: String?, completion: @escaping (Result<Void, Error>) -> Void)
    func fetchPlayerStats(dbId: String, year: String, completion: @escaping (Result<(stats: [(name: String, wins: Int, losses: Int, trueSkill: Double)], years: [String]), Error>) -> Void)
    func setStatsRecomputeRequired(dbId: String, completion: (() -> Void)?)
    func recomputeStatsNow(dbId: String, completion: @escaping (Result<Void, Error>) -> Void)
    func fetchGamesForPlayer(dbId: String, playerName: String, completion: @escaping (Result<[LegacyGame], Error>) -> Void)
    func reserveDatabaseName(displayName: String, completion: @escaping (Result<String, Error>) -> Void)
    func ensureDatabase(dbId: String, displayName: String, completion: @escaping (Result<Void, Error>) -> Void)
    func fetchAdminUIDs(completion: @escaping (Result<[String], Error>) -> Void)
    func fetchDefaultDatabase(completion: @escaping (Result<(dbId: String, displayName: String)?, Error>) -> Void)
    func getDatabaseDocument(dbId: String, completion: @escaping (Result<(displayName: String, isAdmin: Bool), Error>) -> Void)
    func listDatabases(completion: @escaping (Result<[(id: String, displayName: String)], Error>) -> Void)
    func renameDatabase(dbId: String, currentDisplayName: String, newDisplayName: String, completion: @escaping (Result<Void, Error>) -> Void)
    func deleteDatabase(dbId: String, displayName: String, completion: @escaping (Result<Void, Error>) -> Void)
    func createCode(dbId: String, completion: @escaping (Result<String, Error>) -> Void)
    func getCodeDbId(code: String, completion: @escaping (Result<String, Error>) -> Void)
    func fetchAllPlayers(dbId: String, editorDbId: String?, completion: @escaping ([PlayerInfo]) -> Void)
    func fetchActivity(dbId: String, limit: Int, completion: @escaping (Result<[ActivityEntry], Error>) -> Void)
    func fetchPlayerRows(dbId: String, completion: @escaping (Result<[AdminPlayerRow], Error>) -> Void)
    func insertPlayer(dbId: String, displayName: String, firstName: String?, lastName: String?, completion: @escaping (Result<Void, Error>) -> Void)
    func updatePlayer(dbId: String, docId: String, displayName: String, firstName: String?, lastName: String?, completion: @escaping (Result<Void, Error>) -> Void)
    func deletePlayer(dbId: String, docId: String, completion: @escaping (Result<Void, Error>) -> Void)
}

extension SupabaseManager: CloudBackendProtocol {}
