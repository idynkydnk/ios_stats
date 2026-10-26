import Foundation

enum SitePublicLink {
    static func absolute(_ value: String?) -> URL? { value.flatMap(URL.init(string:)) }
    static func recap(_ value: String) -> URL? { nil }
}

@main
struct LocalGamesTests {
    @MainActor static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("games.json")
        let ledger = try SiteLocalGameLedger(url: file)
        let day = SiteStatsFilters.day(Date())
        let fields: [String: Any] = ["winner1": "A", "winner2": "B", "loser1": "C", "loser2": "D", "winner_score": 21, "loser_score": 15, "game_date": day + " 12:34:56", "division": "open", "location": "Beach"]
        let first = try ledger.add(owner: "alice", kind: "doubles", fields: fields)
        let second = try ledger.add(owner: "alice", kind: "doubles", fields: fields)
        precondition(first.id != second.id && first.localID != second.localID)
        precondition(first.fields["client_game_id"] as? String == first.id)
        precondition(first.doublesGame?.winner1 == "A")
        let restored = try SiteLocalGameLedger(url: file)
        precondition(restored.games.count == 2 && restored.games[0].id == first.id)
        var selection = SiteLocalSelection(section: .doubles, year: String(day.prefix(4)))
        var projected = SiteLocalStats.doubles(nil, games: restored.games, selection: selection)!
        precondition(projected.todayGameCount == 2)
        precondition(projected.stats.first { $0.name == "A" }?.wins == 2)
        precondition(projected.stats.first { $0.name == "C" }?.losses == 2)
        precondition(projected.todayStats.first { $0.name == "B" }?.plusMinus == 12)
        // A successful POST must not subtract from an old displayed snapshot.
        try restored.acknowledge(first.id, serverID: 70)
        projected = SiteLocalStats.doubles(nil, games: restored.games, selection: selection)!
        precondition(projected.todayGameCount == 2)
        var base = DoublesStatsPayload(syncedLocalGameIds: [first.id], year: selection.year, displayYear: selection.year, showingPreviousYear: false, minimumGames: 1, allYears: [], stats: [RankingRow(name: "A", wins: 3, losses: 1, winPct: 0.75, rating: 25)], rareStats: [], todayStats: [RankingRow(name: "A", wins: 1, losses: 0, winPct: 1)], todayGameCount: 1)
        projected = SiteLocalStats.doubles(base, games: restored.games, selection: selection)!
        precondition(projected.todayGameCount == 2)
        let a = projected.stats.first { $0.name == "A" }!
        precondition(a.wins == 4 && a.losses == 1 && a.gamesCount == 5 && a.winPct == 0.8 && a.rating == 25 && a.provisional == true)
        base.syncedLocalGameIds = [first.id, second.id]
        base.stats[0].wins = 4
        projected = SiteLocalStats.doubles(base, games: restored.games, selection: selection)!
        precondition(projected.stats[0].wins == 4)
        // Receipt after deletion suppresses an old local copy as well.
        base.stats = []; base.todayStats = []; base.todayGameCount = 0
        precondition(SiteLocalStats.doubles(base, games: restored.games, selection: selection)!.stats.isEmpty)
        selection.division = "women"
        precondition(SiteLocalStats.doubles(nil, games: restored.games, selection: selection) == nil)
        selection.division = "open"; selection.filters.location = "Park"
        precondition(SiteLocalStats.doubles(nil, games: restored.games, selection: selection) == nil)
        selection.filters = SiteStatsFilters(startDay: "2000-01-01", endDay: "2000-01-02")
        precondition(!selection.matches(first))
        selection.filters = SiteStatsFilters(); selection.search = "missing player"
        precondition(!selection.matches(first))
        let tie = try ledger.add(owner: "bob", kind: "other", fields: ["winners": ["P"], "losers": ["Q"], "is_tie": true, "game_type": "Board", "game_name": "Chess", "game_date": day + " 12:00:00"])
        let other = SiteLocalStats.other(nil, games: [tie], selection: SiteLocalSelection(section: .other, year: "All years"))!
        precondition(other.gameCards[0].stats.allSatisfy { $0.ties == 1 && $0.wins == 0 && $0.losses == 0 && $0.gamesCount == 1 })
        precondition(tie.otherGame?.displayWinners == ["P"])
        let singles = try ledger.add(owner: "alice", kind: "other", fields: ["winners": ["A"], "losers": ["C"], "one_on_one": true, "game_name": "No jump", "game_type": "Volleyball", "game_date": day + " 12:00:00"])
        let v = SiteLocalStats.vollis(nil, games: [singles], selection: SiteLocalSelection(section: .vollis, year: "All years", game: "No jump"))!
        precondition(v.stats.first { $0.name == "A" }?.wins == 1)
        precondition(singles.vollisGame?.winner == "A")
        precondition(SiteLocalStats.other(nil, games: [singles], selection: SiteLocalSelection(section: .other, year: "All years")) == nil)
        // Disk failure leaves the in-memory ledger untouched and fails Save.
        let blocked = dir.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let failing = try SiteLocalGameLedger(url: blocked.appendingPathComponent("games.json"))
        do { try failing.add(owner: "alice", kind: "doubles", fields: fields); fatalError("Accepted a failed disk write") } catch { precondition(failing.games.isEmpty) }
        try Data("corrupt".utf8).write(to: file)
        do { _ = try SiteLocalGameLedger(url: file); fatalError("Ignored corrupt saved games") } catch { }
        let preserved = try Data(contentsOf: file)
        precondition(preserved == Data("corrupt".utf8))
        print("Local save, restart, immediate stats, snapshot reconciliation, filters, ties, and disk-failure checks passed")
    }
}
