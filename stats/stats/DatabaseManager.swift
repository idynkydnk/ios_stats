import Foundation
import SQLite3

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.stats.database", qos: .userInitiated)
    
    private init() {
        openDatabase()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func openDatabase() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        // Use new filename so we start fresh (old stats.db is not loaded)
        let destURL = documentsURL.appendingPathComponent("beach_volleyball.db")
        
        if sqlite3_open(destURL.path, &db) != SQLITE_OK {
            print("Error opening database")
            return
        }
        
        createSchemaIfNeeded()
    }
    
    private func createSchemaIfNeeded() {
        let schema = """
            CREATE TABLE IF NOT EXISTS games (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                game_date TEXT NOT NULL,
                winner1 TEXT NOT NULL,
                winner2 TEXT NOT NULL,
                winner_score INTEGER NOT NULL,
                loser1 TEXT NOT NULL,
                loser2 TEXT NOT NULL,
                loser_score INTEGER NOT NULL,
                updated_at TEXT
            )
            """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, schema, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error creating games table")
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Fetch All Games
    
    func fetchAllGames() -> [LegacyGame] {
        var games: [LegacyGame] = []
        
        let query = """
            SELECT id, game_date, winner1, winner2, winner_score, loser1, loser2, loser_score
            FROM games
            ORDER BY game_date DESC
            """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let dateString = safeString(statement, 1)
                let winner1 = safeString(statement, 2)
                let winner2 = safeString(statement, 3)
                let winnerScore = Int(sqlite3_column_int(statement, 4))
                let loser1 = safeString(statement, 5)
                let loser2 = safeString(statement, 6)
                let loserScore = Int(sqlite3_column_int(statement, 7))
                
                let date = parseDate(dateString)
                
                games.append(LegacyGame(
                    id: id,
                    date: date,
                    winner1: winner1,
                    winner2: winner2,
                    winnerScore: winnerScore,
                    loser1: loser1,
                    loser2: loser2,
                    loserScore: loserScore,
                    recordName: nil
                ))
            }
        }
        
        sqlite3_finalize(statement)
        return games
    }
    
    /// Fetches all games; uses CloudKit when a shared database is active, otherwise local SQLite. Completion is called on main thread.
    func fetchAllGames(completion: @escaping ([LegacyGame]) -> Void) {
        if CloudKitManager.shared.hasSharedDatabase {
            CloudKitManager.shared.fetchAllGames { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let games): completion(games)
                    case .failure: completion([])
                    }
                }
            }
        } else {
            completion(fetchAllGames())
        }
    }
    
    // MARK: - Recent Players
    
    func fetchRecentPlayers(limit: Int = 10) -> [PlayerInfo] {
        var players: [PlayerInfo] = []
        
        let query = """
            SELECT player, MAX(game_date) as last_played, COUNT(*) as games
            FROM (
                SELECT winner1 as player, game_date FROM games
                UNION ALL SELECT winner2, game_date FROM games
                UNION ALL SELECT loser1, game_date FROM games
                UNION ALL SELECT loser2, game_date FROM games
            )
            GROUP BY player
            ORDER BY last_played DESC, games DESC
            LIMIT ?
            """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 0))
                let dateString = String(cString: sqlite3_column_text(statement, 1))
                let gameCount = Int(sqlite3_column_int(statement, 2))
                
                players.append(PlayerInfo(
                    name: name,
                    lastPlayed: parseDate(dateString),
                    gameCount: gameCount
                ))
            }
        }
        
        sqlite3_finalize(statement)
        return players
    }
    
    // MARK: - All Players
    
    func fetchAllPlayers() -> [PlayerInfo] {
        var players: [PlayerInfo] = []
        
        let query = """
            SELECT player, MAX(game_date) as last_played, COUNT(*) as games
            FROM (
                SELECT winner1 as player, game_date FROM games
                UNION ALL SELECT winner2, game_date FROM games
                UNION ALL SELECT loser1, game_date FROM games
                UNION ALL SELECT loser2, game_date FROM games
            )
            GROUP BY player
            ORDER BY last_played DESC, games DESC
            """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 0))
                let dateString = String(cString: sqlite3_column_text(statement, 1))
                let gameCount = Int(sqlite3_column_int(statement, 2))
                
                players.append(PlayerInfo(
                    name: name,
                    lastPlayed: parseDate(dateString),
                    gameCount: gameCount
                ))
            }
        }
        
        sqlite3_finalize(statement)
        return players
    }
    
    /// Fetches recent players; when using CloudKit, derives from shared games. Completion on main thread.
    func fetchRecentPlayers(limit: Int = 10, completion: @escaping ([PlayerInfo]) -> Void) {
        if CloudKitManager.shared.hasSharedDatabase {
            CloudKitManager.shared.fetchAllGames { result in
                let games = (try? result.get()) ?? []
                let players = Self.playersFromGames(games)
                DispatchQueue.main.async {
                    completion(Array(players.prefix(limit)))
                }
            }
        } else {
            completion(fetchRecentPlayers(limit: limit))
        }
    }
    
    /// Fetches all players; when using CloudKit, derives from shared games. Completion on main thread.
    func fetchAllPlayers(completion: @escaping ([PlayerInfo]) -> Void) {
        if CloudKitManager.shared.hasSharedDatabase {
            CloudKitManager.shared.fetchAllGames { result in
                let games = (try? result.get()) ?? []
                let players = Self.playersFromGames(games)
                DispatchQueue.main.async {
                    completion(players)
                }
            }
        } else {
            completion(fetchAllPlayers())
        }
    }
    
    private static func playersFromGames(_ games: [LegacyGame]) -> [PlayerInfo] {
        var lastPlayed: [String: Date] = [:]
        var gameCount: [String: Int] = [:]
        for g in games {
            for (name, date) in [(g.winner1, g.date), (g.winner2, g.date), (g.loser1, g.date), (g.loser2, g.date)] where !name.trimmingCharacters(in: .whitespaces).isEmpty {
                if lastPlayed[name] == nil || (lastPlayed[name] ?? .distantPast) < date {
                    lastPlayed[name] = date
                }
                gameCount[name, default: 0] += 1
            }
        }
        return lastPlayed.keys.map { name in
            PlayerInfo(name: name, lastPlayed: lastPlayed[name] ?? Date(), gameCount: gameCount[name] ?? 0)
        }.sorted { ($0.lastPlayed, $0.gameCount) > ($1.lastPlayed, $1.gameCount) }
    }
    
    // MARK: - Insert Game
    
    func insertGame(winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int) -> Bool {
        let query = """
            INSERT INTO games (game_date, winner1, winner2, winner_score, loser1, loser2, loser_score, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        
        var statement: OpaquePointer?
        let now = ISO8601DateFormatter().string(from: Date())
        
        let w1 = capitalizeName(winner1)
        let w2 = capitalizeName(winner2)
        let l1 = capitalizeName(loser1)
        let l2 = capitalizeName(loser2)
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, (now as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, (w1 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, (w2 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 4, Int32(winnerScore))
            sqlite3_bind_text(statement, 5, (l1 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 6, (l2 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 7, Int32(loserScore))
            sqlite3_bind_text(statement, 8, (now as NSString).utf8String, -1, SQLITE_TRANSIENT)
            
            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
        
        return false
    }
    
    /// Inserts a game; uses CloudKit when shared. Completion called on main thread with success.
    func insertGame(winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int,
                    completion: @escaping (Bool) -> Void) {
        if CloudKitManager.shared.hasSharedDatabase {
            CloudKitManager.shared.insertGame(winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore) { result in
                DispatchQueue.main.async {
                    completion((try? result.get()) != nil)
                }
            }
        } else {
            completion(insertGame(winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore))
        }
    }
    
    // MARK: - Update Game
    
    func updateGame(id: Int, winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int) -> Bool {
        let query = """
            UPDATE games SET winner1 = ?, winner2 = ?, winner_score = ?, loser1 = ?, loser2 = ?, loser_score = ?, updated_at = ?
            WHERE id = ?
            """
        var statement: OpaquePointer?
        let now = ISO8601DateFormatter().string(from: Date())
        let w1 = capitalizeName(winner1)
        let w2 = capitalizeName(winner2)
        let l1 = capitalizeName(loser1)
        let l2 = capitalizeName(loser2)
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, (w1 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, (w2 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 3, Int32(winnerScore))
            sqlite3_bind_text(statement, 4, (l1 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, (l2 as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 6, Int32(loserScore))
            sqlite3_bind_text(statement, 7, (now as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 8, Int32(id))
            
            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
        return false
    }
    
    /// Updates a game; uses CloudKit when shared (pass recordName from LegacyGame). Completion on main thread.
    func updateGame(id: Int, recordName: String?, winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int,
                    completion: @escaping (Bool) -> Void) {
        if CloudKitManager.shared.hasSharedDatabase, let name = recordName {
            CloudKitManager.shared.updateGame(recordName: name, winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore) { result in
                DispatchQueue.main.async {
                    completion((try? result.get()) != nil)
                }
            }
        } else {
            completion(updateGame(id: id, winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore))
        }
    }
    
    // MARK: - Delete Game
    
    func deleteGame(id: Int) -> Bool {
        let query = "DELETE FROM games WHERE id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))
            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
        
        return false
    }
    
    /// Deletes a game; uses CloudKit when shared (pass recordName from LegacyGame). Completion on main thread.
    func deleteGame(id: Int, recordName: String?, completion: @escaping (Bool) -> Void) {
        if CloudKitManager.shared.hasSharedDatabase, let name = recordName {
            CloudKitManager.shared.deleteGame(recordName: name) { result in
                DispatchQueue.main.async {
                    completion((try? result.get()) != nil)
                }
            }
        } else {
            completion(deleteGame(id: id))
        }
    }
    
    // MARK: - Helpers
    
    private func safeString(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let ptr = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: ptr)
    }
    
    private func capitalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { word in
                let w = String(word)
                guard let first = w.first else { return w }
                return first.uppercased() + w.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
    
    private func parseDate(_ string: String) -> Date {
        // ISO8601 (used by insert)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        
        // Legacy formats
        let formatters: [DateFormatter] = {
            let f1 = DateFormatter()
            f1.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
            
            let f2 = DateFormatter()
            f2.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            let f3 = DateFormatter()
            f3.dateFormat = "yyyy-MM-dd"
            
            return [f1, f2, f3]
        }()
        
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return Date()
    }
}

// MARK: - Models

struct LegacyGame: Identifiable {
    let id: Int
    let date: Date
    let winner1: String
    let winner2: String
    let winnerScore: Int
    let loser1: String
    let loser2: String
    let loserScore: Int
    /// CloudKit record name when using shared database; nil for local SQLite.
    let recordName: String?
    
    init(id: Int, date: Date, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, recordName: String? = nil) {
        self.id = id
        self.date = date
        self.winner1 = winner1
        self.winner2 = winner2
        self.winnerScore = winnerScore
        self.loser1 = loser1
        self.loser2 = loser2
        self.loserScore = loserScore
        self.recordName = recordName
    }
    
    var winnersDisplay: String {
        let w1 = winner1.trimmingCharacters(in: .whitespaces)
        let w2 = winner2.trimmingCharacters(in: .whitespaces)
        if w1.isEmpty && w2.isEmpty { return "—" }
        if w1.isEmpty { return w2 }
        if w2.isEmpty { return w1 }
        return "\(w1) & \(w2)"
    }
    
    var losersDisplay: String {
        let l1 = loser1.trimmingCharacters(in: .whitespaces)
        let l2 = loser2.trimmingCharacters(in: .whitespaces)
        if l1.isEmpty && l2.isEmpty { return "—" }
        if l1.isEmpty { return l2 }
        if l2.isEmpty { return l1 }
        return "\(l1) & \(l2)"
    }
}

struct PlayerInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let lastPlayed: Date
    let gameCount: Int
}
