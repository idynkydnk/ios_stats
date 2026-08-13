import Combine
import Foundation

/// Local cache of "my database" games. Persisted so the app works offline; synced with Firestore when online.
final class LocalDatabaseCache: ObservableObject {
    static let shared = LocalDatabaseCache()

    @Published private(set) var games: [LegacyGame] = []

    private let keyPrefix = "com.kt.stats.local_cache"
    private let dbIdKey = "db_id"

    private init() {}

    /// Call when myDbId is known. Loads persisted games for that dbId (or empty if none).
    func loadForDatabase(dbId: String?) {
        guard let dbId = dbId else {
            games = []
            return
        }
        let key = "\(keyPrefix)_\(dbId)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CachedGame].self, from: data) else {
            games = []
            return
        }
        games = decoded.map { $0.toLegacyGame() }.sorted { $0.date > $1.date }
    }

    /// Replace cache with cloud data (call when online fetch succeeds).
    func replaceWith(_ newGames: [LegacyGame], dbId: String) {
        games = newGames.sorted { $0.date > $1.date }
        persist(dbId: dbId)
    }

    /// Append a page of older games (e.g. from "Load more"). Keeps sort by date descending.
    func appendPage(_ newGames: [LegacyGame], dbId: String) {
        guard !newGames.isEmpty else { return }
        games = (games + newGames).sorted { $0.date > $1.date }
        persist(dbId: dbId)
    }

    /// Append a game (offline add). Use recordName "offline-\(UUID())".
    func append(_ game: LegacyGame, dbId: String) {
        games.insert(game, at: 0)
        persist(dbId: dbId)
    }

    /// Update an existing game in cache (by recordName).
    func update(recordName: String, with game: LegacyGame, dbId: String) {
        guard let idx = games.firstIndex(where: { $0.recordName == recordName }) else { return }
        games[idx] = game
        persist(dbId: dbId)
    }

    /// Remove a game by recordName.
    func remove(recordName: String, dbId: String) {
        games.removeAll { $0.recordName == recordName }
        persist(dbId: dbId)
    }

    /// Games that were added offline (not yet in Firestore).
    func pendingOfflineGames() -> [LegacyGame] {
        games.filter { ($0.recordName ?? "").hasPrefix("offline-") }
    }

    private func persist(dbId: String) {
        let key = "\(keyPrefix)_\(dbId)"
        let payload = games.map { CachedGame(from: $0) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Persistence payload

private struct CachedGame: Codable {
    let id: Int
    let date: Date
    let winner1: String
    let winner2: String
    let winnerScore: Int
    let loser1: String
    let loser2: String
    let loserScore: Int
    let comment: String?
    let recordName: String?

    init(from game: LegacyGame) {
        id = game.id
        date = game.date
        winner1 = game.winner1
        winner2 = game.winner2
        winnerScore = game.winnerScore
        loser1 = game.loser1
        loser2 = game.loser2
        loserScore = game.loserScore
        comment = game.comment
        recordName = game.recordName
    }

    func toLegacyGame() -> LegacyGame {
        LegacyGame(
            id: id,
            date: date,
            winner1: winner1,
            winner2: winner2,
            winnerScore: winnerScore,
            loser1: loser1,
            loser2: loser2,
            loserScore: loserScore,
            comment: comment ?? "",
            recordName: recordName
        )
    }
}
