import Foundation

/// A game and its upload identity are persisted together before Save succeeds.
nonisolated struct SiteLocalGame: Codable, Identifiable {
    var id: String
    var localID: Int
    var owner: String
    var kind: String
    var body: Data
    var serverID: Int? = nil
    var failure: String? = nil
    var needsAttention = false

    var fields: [String: Any] { (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:] }
    var day: String { String((fields["game_date"] as? String ?? "").prefix(10)) }
    var gameName: String { kind == "doubles" ? "Doubles" : kind == "vollis" ? "Vollis" : fields["game_name"] as? String ?? "" }
    var oneOnOne: Bool { kind == "vollis" || fields["one_on_one"] as? Bool == true }
    var winners: [String] {
        if kind == "doubles" { return ["winner1", "winner2"].compactMap { fields[$0] as? String } }
        if kind == "vollis" { return [fields["winner"] as? String].compactMap { $0 } }
        return fields["winners"] as? [String] ?? []
    }
    var losers: [String] {
        if kind == "doubles" { return ["loser1", "loser2"].compactMap { fields[$0] as? String } }
        if kind == "vollis" { return [fields["loser"] as? String].compactMap { $0 } }
        return fields["losers"] as? [String] ?? []
    }
    var isTie: Bool { fields["is_tie"] as? Bool == true }
    var margin: Int { (fields["winner_score"] as? Int ?? 0) - (fields["loser_score"] as? Int ?? 0) }

    @MainActor func decode<T: Decodable>(_ type: T.Type, extra: [String: Any] = [:]) -> T? {
        var json = fields
        json["id"] = localID
        json["updated_by"] = owner
        json.merge(extra) { _, value in value }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(type, from: JSONSerialization.data(withJSONObject: json))
    }
    @MainActor var doublesGame: DoublesGame? { decode(DoublesGame.self) }
    @MainActor var otherGame: OtherGame? { decode(OtherGame.self) }
    @MainActor var vollisGame: VollisGame? {
        decode(VollisGame.self, extra: ["winner": winners.first ?? "", "loser": losers.first ?? "", "game_name": gameName, "can_edit": false])
    }
}

/// Application Support, not an evictable browse cache. Failed writes never
/// publish a saved game; corrupt files are preserved and block further saves.
nonisolated final class SiteLocalGameLedger {
    let url: URL
    private(set) var games: [SiteLocalGame]

    init(url: URL) throws {
        self.url = url
        games = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode([SiteLocalGame].self, from: Data(contentsOf: url)) : []
    }
    func replace(_ next: [SiteLocalGame]) throws {
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        games = next
    }
    @discardableResult
    func add(owner: String, kind: String, fields: [String: Any]) throws -> SiteLocalGame {
        let id = UUID().uuidString.lowercased()
        var fields = fields
        fields["client_game_id"] = id
        let item = SiteLocalGame(id: id, localID: (games.map(\.localID).min() ?? 0) - 1,
                                 owner: owner, kind: kind, body: try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys))
        try replace(games + [item])
        return item
    }
    func acknowledge(_ id: String, serverID: Int) throws {
        var next = games
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].serverID = serverID
        next[index].failure = nil
        next[index].needsAttention = false
        try replace(next)
    }
}

struct SiteLocalSelection {
    var section: GameSection
    var year: String
    var division = "open"
    var game = ""
    var filters = SiteStatsFilters()
    var search = ""

    func matches(_ item: SiteLocalGame, today: Bool = false, now: Date = Date()) -> Bool {
        let f = item.fields
        switch section {
        case .doubles:
            guard item.kind == "doubles", (f["division"] as? String ?? "open") == division else { return false }
        case .vollis:
            guard item.oneOnOne, game.isEmpty || item.gameName.caseInsensitiveCompare(game) == .orderedSame else { return false }
        case .other:
            guard item.kind == "other", !item.oneOnOne, game.isEmpty || item.gameName.caseInsensitiveCompare(game) == .orderedSame else { return false }
        }
        if today {
            guard item.day == SiteStatsFilters.day(now) else { return false }
        } else if !filters.hasDates && !["All", "All years", ""].contains(year) {
            guard item.day.hasPrefix(year + "-") else { return false }
        }
        if filters.hasDates && (item.day < filters.startDay || item.day > filters.endDay) { return false }
        let location = f["location"] as? String ?? ""
        if filters.missingLocation && !location.isEmpty { return false }
        if !filters.missingLocation && !filters.location.isEmpty && location.caseInsensitiveCompare(filters.location) != .orderedSame { return false }
        let text = (item.winners + item.losers + [item.gameName, location, f["comments"] as? String ?? f["comment"] as? String ?? ""]).joined(separator: " ")
        return search.split { $0.isWhitespace || $0 == "," }.allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
    }
}

/// Overlay only the games absent from this particular server snapshot. A POST
/// acknowledgement alone never removes a game from an older displayed snapshot.
@MainActor
enum SiteLocalStats {
    static func missing(_ games: [SiteLocalGame], included: [String]?) -> [SiteLocalGame] {
        let known = Set(included ?? [])
        return games.filter { !known.contains($0.id) }
    }
    static func rows(_ base: [RankingRow], adding games: [SiteLocalGame]) -> [RankingRow] {
        var rows = base
        for game in games {
            for (names, won) in [(game.winners, true), (game.losers, false)] {
                for name in Set(names) {
                    let index: Int
                    if let found = rows.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { index = found }
                    else { rows.append(RankingRow(name: name, wins: 0, losses: 0, winPct: 0)); index = rows.count - 1 }
                    if game.isTie { rows[index].ties = (rows[index].ties ?? 0) + 1 }
                    else if won { rows[index].wins += 1 }
                    else { rows[index].losses += 1 }
                    let count = rows[index].wins + rows[index].losses + (rows[index].ties ?? 0)
                    rows[index].games = count
                    rows[index].winPct = count == 0 ? 0 : Double(rows[index].wins) / Double(count)
                    rows[index].plusMinus = (rows[index].plusMinus ?? 0) + (won ? game.margin : -game.margin)
                    // Keep the last confirmed rating, explicitly marked provisional.
                    rows[index].provisional = true
                }
            }
        }
        return rows
    }
    static func doubles(_ base: DoublesStatsPayload?, games: [SiteLocalGame], selection: SiteLocalSelection) -> DoublesStatsPayload? {
        let missing = missing(games, included: base?.syncedLocalGameIds)
        let annual = missing.filter { selection.matches($0) }
        let today = missing.filter { selection.matches($0, today: true) }
        guard base != nil || !annual.isEmpty || !today.isEmpty else { return nil }
        var result = base ?? DoublesStatsPayload(year: selection.year, displayYear: selection.year, showingPreviousYear: false, minimumGames: 1, allYears: [], stats: [], rareStats: [], todayStats: [], todayGameCount: 0)
        if result.showingPreviousYear && !annual.isEmpty {
            result.stats = []; result.rareStats = []; result.displayYear = selection.year; result.showingPreviousYear = false
        }
        let all = rows(result.stats + result.rareStats, adding: annual)
        result.stats = all.filter { $0.gamesCount >= result.minimumGames }
        result.rareStats = all.filter { $0.gamesCount < result.minimumGames }
        result.todayStats = rows(result.todayStats, adding: today)
        result.todayGameCount += today.count
        return result
    }
    static func vollis(_ base: VollisStatsPayload?, games: [SiteLocalGame], selection: SiteLocalSelection) -> VollisStatsPayload? {
        let missing = missing(games, included: base?.syncedLocalGameIds)
        let annual = missing.filter { selection.matches($0) }
        let today = missing.filter { selection.matches($0, today: true) }
        guard base != nil || !annual.isEmpty || !today.isEmpty else { return nil }
        var result = base ?? VollisStatsPayload(year: selection.year, displayYear: selection.year, showingPreviousYear: false, allYears: [], stats: [], todayStats: [], todayGameCount: 0)
        if result.showingPreviousYear && !annual.isEmpty { result.stats = []; result.displayYear = selection.year; result.showingPreviousYear = false }
        result.stats = rows(result.stats, adding: annual)
        result.todayStats = rows(result.todayStats ?? [], adding: today)
        result.todayGameCount = (result.todayGameCount ?? 0) + today.count
        return result
    }
    static func other(_ base: OtherStatsPayload?, games: [SiteLocalGame], selection: SiteLocalSelection) -> OtherStatsPayload? {
        let missing = missing(games, included: base?.syncedLocalGameIds)
        let annual = missing.filter { selection.matches($0) }
        let today = missing.filter { selection.matches($0, today: true) }
        guard base != nil || !annual.isEmpty || !today.isEmpty else { return nil }
        var result = base ?? OtherStatsPayload(year: selection.year, displayYear: selection.year, showingPreviousYear: false, allYears: [], stats: [], rareStats: [], gameCards: [], todayStatsByGame: [], todayGames: [])
        if result.showingPreviousYear && !annual.isEmpty {
            result.stats = []; result.rareStats = []; result.gameCards = []; result.displayYear = selection.year; result.showingPreviousYear = false
        }
        let all = rows(result.stats + result.rareStats, adding: annual)
        result.stats = all.filter { $0.gamesCount >= (result.minimumGames ?? 1) }
        result.rareStats = all.filter { $0.gamesCount < (result.minimumGames ?? 1) }
        for (name, additions) in Dictionary(grouping: annual, by: \.gameName) {
            let index: Int
            if let found = result.gameCards.firstIndex(where: { $0.gameName == name }) { index = found }
            else { result.gameCards.append(SiteGameCard(gameName: name, gameType: additions.first?.fields["game_type"] as? String, totalGames: 0, minimumGames: 1, stats: [], rareStats: [])); index = result.gameCards.count - 1 }
            var card = result.gameCards[index]
            let rows = rows(card.stats + card.rareStats, adding: additions)
            card.stats = rows.filter { $0.gamesCount >= (card.minimumGames ?? 1) }
            card.rareStats = rows.filter { $0.gamesCount < (card.minimumGames ?? 1) }
            card.totalGames = (card.totalGames ?? 0) + additions.count
            result.gameCards[index] = card
        }
        for (name, additions) in Dictionary(grouping: today, by: \.gameName) {
            if let index = result.todayStatsByGame.firstIndex(where: { $0.gameName == name }) {
                result.todayStatsByGame[index].stats = rows(result.todayStatsByGame[index].stats, adding: additions)
                result.todayStatsByGame[index].gameCount = (result.todayStatsByGame[index].gameCount ?? 0) + additions.count
            } else {
                result.todayStatsByGame.append(TodayOtherBlock(gameName: name, gameCount: additions.count, stats: rows([], adding: additions)))
            }
        }
        result.todayGames = today.compactMap { $0.otherGame } + result.todayGames
        return result
    }
}
