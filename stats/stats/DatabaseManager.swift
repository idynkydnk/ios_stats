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
                    comment: "",
                    recordName: nil
                ))
            }
        }
        
        sqlite3_finalize(statement)
        return games
    }
    
    /// Fetches all games. Completion is called on main thread.
    func fetchAllGames(completion: @escaping ([LegacyGame]) -> Void) {
        dbQueue.async { [weak self] in
            guard let self else { return }
            let games = self.fetchAllGames()
            DispatchQueue.main.async { completion(games) }
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
    
    /// Fetches recent players. Completion on main thread.
    func fetchRecentPlayers(limit: Int = 10, completion: @escaping ([PlayerInfo]) -> Void) {
        dbQueue.async { [weak self] in
            guard let self else { return }
            let players = self.fetchRecentPlayers(limit: limit)
            DispatchQueue.main.async { completion(players) }
        }
    }

    /// Fetches all players. Completion on main thread.
    func fetchAllPlayers(completion: @escaping ([PlayerInfo]) -> Void) {
        dbQueue.async { [weak self] in
            guard let self else { return }
            let players = self.fetchAllPlayers()
            DispatchQueue.main.async { completion(players) }
        }
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
    
    /// Inserts a game. Completion called on main thread with success.
    func insertGame(winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int,
                    completion: @escaping (Bool) -> Void) {
        dbQueue.async { [weak self] in
            guard let self else { return }
            let success = self.insertGame(winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore)
            DispatchQueue.main.async { completion(success) }
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
    
    /// Updates a game by id. Completion on main thread.
    func updateGame(id: Int, winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int,
                    completion: @escaping (Bool) -> Void) {
        dbQueue.async { [weak self] in
            guard let self else { return }
            let success = self.updateGame(id: id, winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore)
            DispatchQueue.main.async { completion(success) }
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
    
    /// Deletes a game by id. Completion on main thread.
    func deleteGame(id: Int, completion: @escaping (Bool) -> Void) {
        dbQueue.async { [weak self] in
            guard let self else { return }
            let success = self.deleteGame(id: id)
            DispatchQueue.main.async { completion(success) }
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
    let comment: String
    /// Reserved for compatibility; unused with local SQLite.
    let recordName: String?

    init(id: Int, date: Date, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, comment: String = "", recordName: String? = nil) {
        self.id = id
        self.date = date
        self.winner1 = winner1
        self.winner2 = winner2
        self.winnerScore = winnerScore
        self.loser1 = loser1
        self.loser2 = loser2
        self.loserScore = loserScore
        self.comment = comment
        self.recordName = recordName
    }
    
    var winnersDisplay: String {
        let w1 = winner1.trimmingCharacters(in: .whitespaces)
        let w2 = winner2.trimmingCharacters(in: .whitespaces)
        if w1.isEmpty && w2.isEmpty { return "—" }
        if w1.isEmpty { return w2 }
        if w2.isEmpty { return w1 }
        return "\(w1) \(w2)"
    }
    
    var losersDisplay: String {
        let l1 = loser1.trimmingCharacters(in: .whitespaces)
        let l2 = loser2.trimmingCharacters(in: .whitespaces)
        if l1.isEmpty && l2.isEmpty { return "—" }
        if l1.isEmpty { return l2 }
        if l2.isEmpty { return l1 }
        return "\(l1) \(l2)"
    }
}

/// Stored player in Firestore (databases/{dbId}/players). First and last name required; rest optional.
struct Player: Identifiable, Hashable {
    var id: String { documentId ?? displayName }
    let documentId: String?
    let firstName: String
    let lastName: String
    let email: String?
    let age: Int?
    let height: Double?
    let dateOfBirth: Date?
    let comment: String?

    var displayName: String {
        [firstName, lastName].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    init(documentId: String? = nil, firstName: String, lastName: String, email: String? = nil, age: Int? = nil, height: Double? = nil, dateOfBirth: Date? = nil, comment: String? = nil) {
        self.documentId = documentId
        self.firstName = firstName.trimmingCharacters(in: .whitespaces)
        self.lastName = lastName.trimmingCharacters(in: .whitespaces)
        self.email = email
        self.age = age
        self.height = height
        self.dateOfBirth = dateOfBirth
        self.comment = comment
    }
}

struct PlayerInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let lastPlayed: Date
    let gameCount: Int
    /// When the current user last added/edited a game containing this player (for autocomplete sort). Nil when unknown.
    let lastAddedByEditor: Date?
    
    init(name: String, lastPlayed: Date, gameCount: Int, lastAddedByEditor: Date? = nil) {
        self.name = name
        self.lastPlayed = lastPlayed
        self.gameCount = gameCount
        self.lastAddedByEditor = lastAddedByEditor
    }
}
