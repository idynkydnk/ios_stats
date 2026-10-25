import Foundation

struct SiteSeason: Decodable, Identifiable {
    var id: String
    var name: String
    var startDate: String
    var endDate: String
    var minimumGames: Int?
    var minimumMode: String
    var timezone: String
    var status: String
    var shareUrl: String?

    var dates: String { "\(startDate) – \(endDate)" }
    var minimumDescription: String {
        minimumGames.map { "\($0) games per player to qualify" } ?? "Automatic minimum games"
    }
}

struct SiteSeasonPlayer: Decodable, Identifiable {
    var name: String
    var wins: Int
    var losses: Int
    var ties: Int
    var games: Int
    var winPct: Double
    var rating: Double?
    var firstRating: Double?
    var ratingGain: Double?
    var gamesNeeded: Int
    var qualified: Bool
    var id: String { name }
    var winPercent: String { String(format: "%.0f%%", winPct * 100) }
    var ratingText: String { rating.map { String(format: "%.2f", $0) } ?? "—" }
}

struct SiteSeasonGroup: Decodable, Identifiable {
    var id: String
    var title: String
    var gameCount: Int
    var minimumGames: Int
    var ratingEnabled: Bool
    var ratedGames: Int
    var unratedGames: Int
    var stats: [SiteSeasonPlayer]
    var rareStats: [SiteSeasonPlayer]
    var champions: [SiteSeasonPlayer]
    var mostImproved: [SiteSeasonPlayer]
    var awardMetric: String
}

struct SiteSeasonChampion: Decodable, Identifiable {
    var seasonId: String
    var seasonName: String
    var startDate: String
    var endDate: String
    var groupId: String
    var groupTitle: String
    var name: String
    var winPct: Double
    var rating: Double?
    var id: String { "\(seasonId)|\(groupId)|\(name)" }
}

struct SiteSeasonsPayload: Decodable {
    var seasons: [SiteSeason]
    var champions: [SiteSeasonChampion]
}

struct SiteSeasonGame: Decodable, Identifiable {
    var id: String
    var day: String
    var winners: [String]
    var losers: [String]
    var winnerScore: Int?
    var loserScore: Int?
    var result: String
}

struct SiteSeasonPlayerDetail: Decodable {
    var stats: SiteSeasonPlayer
    var groupTitle: String
    var games: [SiteSeasonGame]
}

struct SiteSeasonPayload: Decodable {
    var season: SiteSeason
    var groups: [SiteSeasonGroup]
    var gameCount: Int
    var minimumExplanation: String
    var awardsExplanation: String
    var player: SiteSeasonPlayerDetail?
}

struct SiteSeasonDraft {
    var name = ""
    var startDate = Date()
    var endDate = Date()
    var automatic = true
    var minimum = "1"

    static let minimumExplanation = "Automatic uses the same rule as the site: divide the number of games in each season standings group by 30, round down, and use at least 1. For example, 90 games means a player needs 3 games to qualify. It grows with participation, so a busy season asks for more games without making a quieter season too hard to qualify for. Choose a fixed minimum if your league needs a specific target."

    init(season: SiteSeason? = nil) {
        if let season {
            name = season.name
            startDate = Self.date(season.startDate) ?? Date()
            endDate = Self.date(season.endDate) ?? startDate
            automatic = season.minimumGames == nil
            minimum = String(season.minimumGames ?? 1)
        }
    }

    var validationError: String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty || cleanName.count > 80 { return "Give the season a name of 1–80 characters." }
        if Self.day(endDate) < Self.day(startDate) { return "The end day must be on or after the start day." }
        if !automatic, Int(minimum).map({ (1...100000).contains($0) }) != true {
            return "Minimum games must be a whole number from 1 to 100,000."
        }
        return nil
    }

    var fields: [String: Any] {
        var value: [String: Any] = ["name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "start_date": Self.day(startDate), "end_date": Self.day(endDate),
            "minimum_mode": automatic ? "automatic" : "fixed", "timezone": TimeZone.current.identifier]
        if !automatic { value["minimum_games"] = Int(minimum) ?? 0 }
        return value
    }

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f
    }
    static func day(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ day: String) -> Date? { formatter.date(from: day) }
}

/// A later refresh or account change makes earlier responses ineligible to display.
struct SiteSeasonLoadGate {
    struct Ticket: Equatable {
        let id = UUID()
        let account: String?
    }
    private var latest: Ticket?
    mutating func begin(account: String?) -> Ticket {
        let ticket = Ticket(account: account)
        latest = ticket
        return ticket
    }
    func accepts(_ ticket: Ticket, account: String?) -> Bool {
        latest == ticket && ticket.account == account
    }
    mutating func invalidate() { latest = nil }
}
