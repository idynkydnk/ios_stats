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

    enum CodingKeys: String, CodingKey {
        case name, wins, losses, winPct, games, rating, plusMinus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        wins = Self.int(c, .wins)
        losses = Self.int(c, .losses)
        winPct = Self.double(c, .winPct)
        games = Self.optionalInt(c, .games)
        rating = Self.optionalDouble(c, .rating)
        plusMinus = Self.optionalInt(c, .plusMinus)
    }

    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int {
        optionalInt(c, key) ?? 0
    }

    private static func optionalInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let v = try? c.decode(Double.self, forKey: key) { return Int(v) }
        if let v = try? c.decode(String.self, forKey: key) { return Int(v) }
        return nil
    }

    private static func double(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double {
        optionalDouble(c, key) ?? 0
    }

    private static func optionalDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let v = try? c.decode(Double.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
        if let v = try? c.decode(String.self, forKey: key) { return Double(v) }
        return nil
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

    func asLegacyGame() -> LegacyGame {
        LegacyGame(
            id: id,
            date: date,
            winner1: winner1 ?? "",
            winner2: winner2 ?? "",
            winnerScore: winnerScore ?? 0,
            loser1: loser1 ?? "",
            loser2: loser2 ?? "",
            loserScore: loserScore ?? 0,
            comment: comment,
            recordName: String(id)
        )
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        for f in formats {
            df.dateFormat = f
            if let d = df.date(from: String(s.prefix(f.count + 4))) { return d }
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
    var winners: [String]?
    var losers: [String]?
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

    var displayWinners: [String] {
        if let winners, !winners.isEmpty { return winners }
        return [winner1, winner2].compactMap { $0 }.filter { !$0.isEmpty }
    }

    var displayLosers: [String] {
        if let losers, !losers.isEmpty { return losers }
        return [loser1, loser2].compactMap { $0 }.filter { !$0.isEmpty }
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
    var aiImageTraits: [String]?

    var id: String { "\(playerId ?? 0)-\(name)" }

    enum CodingKeys: String, CodingKey {
        case playerId = "id"
        case name, nickname, email, dateOfBirth, height, games, firstGame, photoUrl, aiImageTraits
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

struct ActivityEntrySite: Codable, Identifiable {
    var id: Int?
    var username: String?
    var action: String?
    var summary: String?
    var createdAt: String?
    var undone: Bool?
}

struct SiteUser: Codable, Identifiable {
    var username: String
    var isAdmin: Bool?
    var active: Bool?
    var createdAt: String?
    var lastSeen: String?
    var lastLogin: String?
    var id: String { username }
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
