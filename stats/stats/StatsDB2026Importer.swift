import Foundation
import SQLite3

/// Loads 2026 doubles games from a bundled stats.db for importing into the cloud.
enum StatsDB2026Importer {
    struct GameRow {
        let date: Date
        let winner1: String
        let winner2: String
        let winnerScore: Int
        let loser1: String
        let loser2: String
        let loserScore: Int
        let comment: String
    }

    /// Load all 2026 doubles games from bundled stats.db. Completion on main thread.
    static func load2026DoublesGames(completion: @escaping (Result<[GameRow], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let games = loadFromBundleStatsDB() {
                DispatchQueue.main.async { completion(.success(games)) }
                return
            }
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "StatsDB2026Importer", code: 0, userInfo: [NSLocalizedDescriptionKey: "No stats.db found in app bundle. Add stats.db to the Xcode project (with your 2026 doubles games)."])))
            }
        }
    }

    /// Try to load from Bundle resource "stats.db" (SQLite). Expects a table "games" or "doubles_games" with game_date, winner1, winner2, winner_score, loser1, loser2, loser_score, comments.
    private static func loadFromBundleStatsDB() -> [GameRow]? {
        guard let url = Bundle.main.url(forResource: "stats", withExtension: "db") else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = db else { return nil }
        defer { sqlite3_close(db) }

        let tables = ["doubles_games", "games"]
        for table in tables {
            let sql = """
                SELECT game_date, winner1, winner2, winner_score, loser1, loser2, loser_score, COALESCE(comments, '')
                FROM \(table)
                WHERE game_date LIKE '2026%'
                ORDER BY game_date
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement = statement else { continue }
            defer { sqlite3_finalize(statement) }

            var rows: [GameRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let dateStr = String(cString: sqlite3_column_text(statement, 0))
                let winner1 = String(cString: sqlite3_column_text(statement, 1))
                let winner2 = String(cString: sqlite3_column_text(statement, 2))
                let winnerScore = Int(sqlite3_column_int(statement, 3))
                let loser1 = String(cString: sqlite3_column_text(statement, 4))
                let loser2 = String(cString: sqlite3_column_text(statement, 5))
                let loserScore = Int(sqlite3_column_int(statement, 6))
                let comment = sqlite3_column_count(statement) > 7 && sqlite3_column_text(statement, 7) != nil
                    ? String(cString: sqlite3_column_text(statement, 7))
                    : ""
                guard let date = parseDate(dateStr) else { continue }
                rows.append(GameRow(date: date, winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore, comment: comment))
            }
            if !rows.isEmpty { return rows }
        }
        return nil
    }

    private static func parseDate(_ s: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: s) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        if let d = formatter.date(from: s) { return d }
        let legacy = DateFormatter()
        legacy.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = legacy.date(from: s) { return d }
        legacy.dateFormat = "yyyy-MM-dd"
        return legacy.date(from: s)
    }

}
