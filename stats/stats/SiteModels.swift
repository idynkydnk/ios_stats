import Foundation

enum GameSection: String, CaseIterable, Identifiable {
    case doubles, vollis, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .doubles: return "Doubles"
        case .vollis: return "Vollis"
        case .other: return "Other"
        }
    }
}

struct RankingRow: Codable, Identifiable {
    var name: String
    var wins: Int
    var losses: Int
    var winPct: Double
    var games: Int?
    var rating: Double?
    var plusMinus: Int?

    var id: String { name }

    var winPctDisplay: String {
        let pct = winPct <= 1.0 ? winPct * 100 : winPct
        return String(format: "%.0f%%", pct)
    }

    var gamesCount: Int { games ?? (wins + losses) }

    /// Fraction 0...1, whether the API sent 0.75 or 75.
    var winPctFraction: Double { winPct > 1.0 ? winPct / 100.0 : winPct }

    /// Website today tables: win% desc, then +/- desc, then wins desc.
    static func sortedForToday(_ rows: [RankingRow]) -> [RankingRow] {
        rows.sorted { a, b in
            if abs(a.winPctFraction - b.winPctFraction) > 0.0001 {
                return a.winPctFraction > b.winPctFraction
            }
            let aPM = a.plusMinus ?? 0
            let bPM = b.plusMinus ?? 0
            if aPM != bPM { return aPM > bPM }
            if a.wins != b.wins { return a.wins > b.wins }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    init(name: String, wins: Int, losses: Int, winPct: Double, games: Int? = nil, rating: Double? = nil, plusMinus: Int? = nil) {
        self.name = name
        self.wins = wins
        self.losses = losses
        self.winPct = winPct
        self.games = games
        self.rating = rating
        self.plusMinus = plusMinus
    }

    enum CodingKeys: String, CodingKey {
        case name, wins, losses, winPct, games, rating, plusMinus
    }

    private enum AltKeys: String, CodingKey {
        case win_pct, plus_minus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AltKeys.self)
        name = try c.decode(String.self, forKey: .name)
        wins = Self.int(c, .wins)
        losses = Self.int(c, .losses)
        winPct = Self.optionalDouble(c, .winPct) ?? Self.optionalDouble(alt, .win_pct) ?? 0
        games = Self.optionalInt(c, .games)
        rating = Self.optionalDouble(c, .rating)
        plusMinus = Self.optionalInt(c, .plusMinus) ?? Self.optionalInt(alt, .plus_minus)
    }

    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int {
        optionalInt(c, key) ?? 0
    }

    private static func optionalInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let v = try? c.decode(Double.self, forKey: key) { return Int(v) }
        if let v = try? c.decode(String.self, forKey: key) { return Int(v) }
        return nil
    }

    private static func optionalDouble<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let v = try? c.decode(Double.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
        if let v = try? c.decode(String.self, forKey: key) { return Double(v) }
        return nil
    }

    static func todayStats(fromVollis games: [VollisGame]) -> [RankingRow] {
        var map: [String: (wins: Int, losses: Int, plusMinus: Int)] = [:]
        for game in games {
            let margin = (game.winnerScore ?? 0) - (game.loserScore ?? 0)
            if let winner = game.winner?.trimmingCharacters(in: .whitespaces), !winner.isEmpty {
                let cur = map[winner] ?? (0, 0, 0)
                map[winner] = (cur.wins + 1, cur.losses, cur.plusMinus + margin)
            }
            if let loser = game.loser?.trimmingCharacters(in: .whitespaces), !loser.isEmpty {
                let cur = map[loser] ?? (0, 0, 0)
                map[loser] = (cur.wins, cur.losses + 1, cur.plusMinus - margin)
            }
        }
        return map.map { name, s in
            let played = s.wins + s.losses
            return RankingRow(
                name: name,
                wins: s.wins,
                losses: s.losses,
                winPct: played > 0 ? Double(s.wins) / Double(played) : 0,
                plusMinus: s.plusMinus
            )
        }
    }
}

struct DoublesStatsPayload: Codable {
    var year: String
    var displayYear: String
    var showingPreviousYear: Bool
    var minimumGames: Int
    var allYears: [String]
    var stats: [RankingRow]
    var rareStats: [RankingRow]
    var todayStats: [RankingRow]
    var todayGameCount: Int
}

struct DoublesGame: Codable, Identifiable, Hashable {
    var id: Int
    var gameDate: String?
    var winner1: String?
    var winner2: String?
    var winnerScore: Int?
    var loser1: String?
    var loser2: String?
    var loserScore: Int?
    var updatedAt: String?
    var comments: String?
    var enteredTimezone: String?
    var updatedBy: String?

    var date: Date {
        Self.parseDate(gameDate) ?? Date.distantPast
    }

    var comment: String { comments ?? "" }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Site dates often end with a zone label, e.g. "03/18/2026 07:11 PM (PDT)".
        // Drop it and parse as a local calendar date so the listed day matches the site.
        if s.hasSuffix(")"), let open = s.lastIndex(of: "(") {
            s = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        }
        s = s.replacingOccurrences(of: "T", with: " ")
        if s.hasSuffix("Z") { s.removeLast() }

        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy hh:mm:ss a",
            "MM/dd/yyyy h:mm:ss a",
            "MM/dd/yyyy hh:mm a",
            "MM/dd/yyyy h:mm a",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy",
            "MM/dd/yy hh:mm a",
            "MM/dd/yy h:mm a",
            "MM/dd/yy",
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        for f in formats {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return ISO8601DateFormatter().date(from: raw)
    }
}

struct GamesListPayload<T: Codable>: Codable {
    var games: [T]
    var deletedIds: [Int]?
    var allYears: [String]?
}

struct MatchupRow: Codable, Identifiable {
    var partner: String?
    var opponent: String?
    var wins: Int
    var losses: Int
    var winPercentage: Double
    var totalGames: Int
    var id: String { (partner ?? opponent ?? "") + "-\(totalGames)-\(wins)" }
}

struct StreakInfo: Codable {
    var type: String
    var length: Int
}

struct DoublesPlayerPayload: Codable {
    var name: String
    var year: String
    var allYears: [String]
    var stats: RankingRow?
    var rating: Double?
    var rank: Int?
    var totalRanked: Int?
    var currentStreak: StreakInfo?
    var recentForm: [String]?
    var partnerMinGames: Int?
    var partners: [MatchupRow]?
    var opponents: [MatchupRow]?
    var games: [DoublesGame]?
    var photoUrl: String?
    var nickname: String?
    var height: String?
    var dateOfBirth: String?
    var email: String?

    enum CodingKeys: String, CodingKey {
        case name, year, allYears, stats, rating, rank, totalRanked
        case currentStreak, recentForm, partnerMinGames, partners, opponents
        case games, photoUrl, nickname, height, dateOfBirth, email
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        allYears = try c.decodeIfPresent([String].self, forKey: .allYears) ?? []
        stats = try? c.decode(RankingRow.self, forKey: .stats)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank)
        totalRanked = try c.decodeIfPresent(Int.self, forKey: .totalRanked)
        currentStreak = try? c.decode(StreakInfo.self, forKey: .currentStreak)
        recentForm = try c.decodeIfPresent([String].self, forKey: .recentForm)
        partnerMinGames = try c.decodeIfPresent(Int.self, forKey: .partnerMinGames)
        partners = try? c.decode([MatchupRow].self, forKey: .partners)
        opponents = try? c.decode([MatchupRow].self, forKey: .opponents)
        games = try? c.decode([DoublesGame].self, forKey: .games)
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        height = try c.decodeIfPresent(String.self, forKey: .height)
        dateOfBirth = try c.decodeIfPresent(String.self, forKey: .dateOfBirth)
        email = try c.decodeIfPresent(String.self, forKey: .email)
    }
}

struct VollisGame: Codable, Identifiable, Hashable {
    var id: Int
    var gameDate: String?
    var winner: String?
    var winnerScore: Int?
    var loser: String?
    var loserScore: Int?
    var updatedAt: String?
    var enteredTimezone: String?

    var date: Date { DoublesGame.parseDate(gameDate) ?? Date.distantPast }
}

struct VollisStatsPayload: Codable {
    var year: String
    var displayYear: String
    var showingPreviousYear: Bool
    var allYears: [String]
    var stats: [RankingRow]
    var todayStats: [RankingRow]?
    var todayGameCount: Int?
}

struct OtherGamePlayer: Codable, Hashable {
    var name: String
    var score: Int?

    init(name: String, score: Int? = nil) {
        self.name = name
        self.score = score
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            name = s
            score = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        score = Self.optionalInt(c, .score)
    }

    enum CodingKeys: String, CodingKey { case name, score }

    private static func optionalInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let v = try? c.decode(Double.self, forKey: key) { return Int(v) }
        if let v = try? c.decode(String.self, forKey: key) { return Int(v) }
        return nil
    }
}

struct OtherGame: Codable, Identifiable, Hashable {
    var gameId: Int?
    var jsonId: Int?
    var gameDate: String?
    var gameDateOnly: String?
    var gameType: String?
    var gameName: String?
    var comment: String?
    var updatedAt: String?
    var winnerScore: Int?
    var loserScore: Int?
    var winners: [OtherGamePlayer]?
    var losers: [OtherGamePlayer]?
    var winner1: String?
    var winner2: String?
    var loser1: String?
    var loser2: String?

    var id: Int { jsonId ?? gameId ?? 0 }

    enum CodingKeys: String, CodingKey {
        case gameId, gameDate, gameDateOnly, gameType, gameName, comment, updatedAt
        case winnerScore, loserScore, winners, losers, winner1, winner2, loser1, loser2
        case jsonId = "id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameId = Self.optionalInt(c, .gameId)
        jsonId = Self.optionalInt(c, .jsonId)
        gameDate = try c.decodeIfPresent(String.self, forKey: .gameDate)
        gameDateOnly = try c.decodeIfPresent(String.self, forKey: .gameDateOnly)
        gameType = try c.decodeIfPresent(String.self, forKey: .gameType)
        gameName = try c.decodeIfPresent(String.self, forKey: .gameName)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        winnerScore = Self.optionalInt(c, .winnerScore)
        loserScore = Self.optionalInt(c, .loserScore)
        winners = Self.decodePlayers(c, .winners)
        losers = Self.decodePlayers(c, .losers)
        winner1 = try c.decodeIfPresent(String.self, forKey: .winner1)
        winner2 = try c.decodeIfPresent(String.self, forKey: .winner2)
        loser1 = try c.decodeIfPresent(String.self, forKey: .loser1)
        loser2 = try c.decodeIfPresent(String.self, forKey: .loser2)
    }

    var displayWinners: [String] {
        let names = (winners ?? []).map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { return names }
        return [winner1, winner2].compactMap { $0 }.filter { !$0.isEmpty }
    }

    var displayLosers: [String] {
        let names = (losers ?? []).map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { return names }
        return [loser1, loser2].compactMap { $0 }.filter { !$0.isEmpty }
    }

    private static func optionalInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let v = try? c.decode(Double.self, forKey: key) { return Int(v) }
        if let v = try? c.decode(String.self, forKey: key) { return Int(v) }
        return nil
    }

    private static func decodePlayers(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [OtherGamePlayer]? {
        if let players = try? c.decode([OtherGamePlayer].self, forKey: key) { return players }
        if let names = try? c.decode([String].self, forKey: key) {
            return names.map { OtherGamePlayer(name: $0) }
        }
        return nil
    }
}

struct SiteGameCard: Codable, Identifiable {
    var gameName: String?
    var gameType: String?
    var isConsolidated: Bool?
    var totalGames: Int?
    var minimumGames: Int?
    var stats: [RankingRow]
    var rareStats: [RankingRow]
    var id: String { (gameName ?? "") + "|" + (gameType ?? "") }
}

struct OtherStatsPayload: Codable {
    var year: String
    var displayYear: String
    var showingPreviousYear: Bool
    var minimumGames: Int?
    var allYears: [String]
    var stats: [RankingRow]
    var rareStats: [RankingRow]
    var gameCards: [SiteGameCard]
    var todayStatsByGame: [TodayOtherBlock]
    var todayGames: [OtherGame]
}

struct TodayOtherBlock: Codable, Identifiable {
    var gameName: String?
    var gameCount: Int?
    var stats: [RankingRow]
    var id: String { gameName ?? "today" }
}

struct SitePlayer: Codable, Identifiable {
    var playerId: Int?
    var name: String
    var nickname: String?
    var email: String?
    var dateOfBirth: String?
    var height: String?
    var games: Int?
    var firstGame: String?
    var photoUrl: String?
    var aiImageUrl: String?
    var aiImageTraits: [String]?

    var id: String { "\(playerId ?? 0)-\(name)" }

    var isReadyForIllustration: Bool {
        !(photoUrl ?? "").isEmpty
            || !(aiImageUrl ?? "").isEmpty
            || !(aiImageTraits ?? []).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case playerId = "id"
        case name, nickname, email, dateOfBirth, height, games, firstGame, photoUrl, aiImageUrl, aiImageTraits
    }
}

struct Tournament: Codable, Identifiable {
    var id: Int
    var tournamentDate: String?
    var place: String?
    var team: String?
    var location: String?
    var tournamentName: String?
}

struct NetworkPayload: Codable {
    var year: String
    var displayYear: String
    var allYears: [String]
    var network: NetworkData
}

struct NetworkData: Codable {
    var nodes: [NetworkNode]
    var partnerEdges: [NetworkEdge]
    var gameEdges: [NetworkEdge]
}

struct NetworkNode: Codable, Identifiable {
    var id: String
    var label: String?
    var games: Int?
}

struct NetworkEdge: Codable, Identifiable {
    var source: String
    var target: String
    var games: Int?
    var wins: Int?
    var losses: Int?
    var winRate: Double?
    var id: String { source + "-" + target }
}

struct TodaysDoublesDashboard {
    var year: String
    var stats: [RankingRow]
    var games: [DoublesGame]
}

struct YearsPayload: Codable {
    var doubles: [String]
    var vollis: [String]
    var other: [String]
}

struct MePayload: Codable {
    var username: String
    var isAdmin: Bool
    var loggedIn: Bool
}

struct SiteUser: Codable, Identifiable {
    var username: String
    var isAdmin: Bool?
    var active: Bool?
    var createdAt: String?
    var lastSeen: String?
    var lastLogin: String?
    var id: String { username }

    var isAdminUser: Bool { isAdmin == true }
    var isActiveUser: Bool { active ?? true }
}

struct AdminGameCounts: Codable {
    var today: Int
    var week: Int
    var total: Int
}

struct AdminCounts: Codable {
    var doubles: AdminGameCounts
    var vollis: AdminGameCounts
    var other: AdminGameCounts
}

struct AdminRecentGame: Codable {
    var kind: String?
    var gameDate: String?
    var summary: String?
}

struct AdminActionCount: Codable, Identifiable {
    var action: String
    var count: Int
    var id: String { action }
}

struct AdminActivityStats: Codable {
    var total: Int
    var today: Int
    var todayByAction: [AdminActionCount]

    enum CodingKeys: String, CodingKey {
        case total, today, todayByAction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        today = (try? c.decode(Int.self, forKey: .today)) ?? 0
        todayByAction = (try? c.decode([AdminActionCount].self, forKey: .todayByAction)) ?? []
    }
}

struct AdminOverview: Codable {
    var counts: AdminCounts
    var recentGame: AdminRecentGame?
    var dbSizeMb: Double?
    var users: [SiteUser]
    var emailConfigured: Bool
    var activity: AdminActivityStats?

    enum CodingKeys: String, CodingKey {
        case counts, recentGame, dbSizeMb, users, emailConfigured, activity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counts = try c.decode(AdminCounts.self, forKey: .counts)
        recentGame = try c.decodeIfPresent(AdminRecentGame.self, forKey: .recentGame)
        if let d = try? c.decode(Double.self, forKey: .dbSizeMb) {
            dbSizeMb = d
        } else if let i = try? c.decode(Int.self, forKey: .dbSizeMb) {
            dbSizeMb = Double(i)
        } else {
            dbSizeMb = nil
        }
        users = try c.decodeIfPresent([SiteUser].self, forKey: .users) ?? []
        if c.contains(.emailConfigured) {
            emailConfigured = AdminJSON.bool(c, .emailConfigured)
        } else {
            emailConfigured = true
        }
        activity = try c.decodeIfPresent(AdminActivityStats.self, forKey: .activity)
    }
}

struct AdminActivityChange: Codable, Identifiable {
    var field: String
    var before: String?
    var after: String?
    var id: String { field }

    static func diff(beforeJSON: String?, afterJSON: String?) -> [AdminActivityChange] {
        func parse(_ raw: String?) -> [String: Any] {
            guard let raw, let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return obj
        }
        let before = parse(beforeJSON)
        let after = parse(afterJSON)
        if before.isEmpty && after.isEmpty { return [] }
        let keys = Set(before.keys).union(after.keys).sorted()
        return keys.compactMap { key in
            if key == "password_hash" { return nil }
            let old = before[key]
            let new = after[key]
            if !before.isEmpty && !after.isEmpty && String(describing: old ?? "") == String(describing: new ?? "") {
                return nil
            }
            return AdminActivityChange(
                field: key,
                before: old.map { String(describing: $0) },
                after: new.map { String(describing: $0) }
            )
        }
    }
}

struct AdminActivityEntry: Codable, Identifiable {
    var id: Int
    var createdAt: String?
    var username: String
    var action: String
    var target: String?
    var targetId: Int?
    var summary: String?
    var undone: Bool
    var undoable: Bool
    var undoKind: String?
    var beforeJson: String?
    var afterJson: String?
    var changes: [AdminActivityChange]?

    var resolvedChanges: [AdminActivityChange] {
        if let changes, !changes.isEmpty { return changes }
        return AdminActivityChange.diff(beforeJSON: beforeJson, afterJSON: afterJson)
    }

    var targetLabel: String? {
        switch target {
        case "doubles_game": return "Doubles"
        case "vollis_game": return "Vollis"
        case "other_game": return "Other"
        default: return target?.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var undoLabel: String {
        if let undoKind, !undoKind.isEmpty { return "Undo \(undoKind)" }
        return "Undo"
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, username, action, target, targetId, summary
        case undone, undoable, undoKind, beforeJson, afterJson, changes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Int.self, forKey: .id) {
            id = v
        } else if let v = try? c.decode(String.self, forKey: .id), let i = Int(v) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Missing activity id")
        }
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        action = (try? c.decode(String.self, forKey: .action)) ?? ""
        target = try c.decodeIfPresent(String.self, forKey: .target)
        if let v = try? c.decode(Int.self, forKey: .targetId) {
            targetId = v
        } else if let v = try? c.decode(String.self, forKey: .targetId) {
            targetId = Int(v)
        } else {
            targetId = nil
        }
        summary = try? c.decode(String.self, forKey: .summary)
        undone = AdminJSON.bool(c, .undone)
        beforeJson = try? c.decode(String.self, forKey: .beforeJson)
        afterJson = try? c.decode(String.self, forKey: .afterJson)
        let decodedUndoable = c.contains(.undoable) ? AdminJSON.bool(c, .undoable) : nil
        undoable = decodedUndoable ?? (
            !undone
            && targetId != nil
            && ["doubles_game", "vollis_game", "other_game"].contains(target ?? "")
            && (beforeJson != nil || afterJson != nil)
        )
        undoKind = try? c.decode(String.self, forKey: .undoKind)
        changes = try? c.decode([AdminActivityChange].self, forKey: .changes)
    }
}

struct AdminActivityPage: Codable {
    var entries: [AdminActivityEntry]
    var page: Int
    var total: Int
    var totalPages: Int?
    var perPage: Int?

    enum CodingKeys: String, CodingKey {
        case entries, page, total, totalPages, perPage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([AdminActivityEntry].self, forKey: .entries) ?? []
        page = (try? c.decode(Int.self, forKey: .page)) ?? 1
        total = (try? c.decode(Int.self, forKey: .total)) ?? entries.count
        totalPages = try? c.decode(Int.self, forKey: .totalPages)
        perPage = try? c.decode(Int.self, forKey: .perPage)
    }

    var hasMore: Bool {
        if let totalPages { return page < totalPages }
        return entries.count < total
    }
}

private enum AdminJSON {
    static func bool<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool {
        if let v = try? c.decode(Bool.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return v != 0 }
        if let v = try? c.decode(String.self, forKey: key) {
            return ["1", "true", "yes"].contains(v.lowercased())
        }
        return false
    }
}

struct RecapItem: Codable, Identifiable {
    var shareId: String?
    var createdAt: String?
    var heroImageUrl: String?
    var shareUrl: String?
    var headline: String?
    var summary: String?
    var id: String { shareId ?? [createdAt, headline].compactMap { $0 }.joined(separator: "|") }
}

struct FlyerItem: Codable, Identifiable {
    var shareId: String?
    var createdAt: String?
    var flyerImageUrl: String?
    var downloadUrl: String?
    var viewUrl: String?
    var title: String?
    var players: [String]?
    var gameType: String?
    var eventDate: String?
    var eventTime: String?
    var location: String?
    var id: String { shareId ?? [createdAt, title].compactMap { $0 }.joined(separator: "|") }
}

struct OfflineMutation: Codable, Identifiable {
    var id: String
    var method: String
    var path: String
    var body: Data?
}

enum SiteAPIError: LocalizedError {
    case message(String)
    case http(Int, String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        case .http(let code, let s): return s.isEmpty ? "HTTP \(code)" : s
        case .unauthorized: return "Please log in."
        }
    }
}
