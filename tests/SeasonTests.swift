import Foundation

@main
struct SeasonTests {
    static func main() throws {
        // Recorded from the real website API using synthetic, isolated test accounts.
        struct Contract: Decodable {
            var detail: SiteSeasonPayload
            var library: SiteSeasonsPayload
            var player: SiteSeasonPayload
        }
        let path = CommandLine.arguments.dropFirst().first ?? "tests/fixtures/season-contract.json"
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let contract = try decoder.decode(Contract.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let detail = contract.detail
        precondition(detail.season.name == "Winter league")
        precondition(detail.season.minimumGames == nil && detail.season.shareUrl == nil)
        precondition(detail.season.status == "Completed")
        precondition(detail.gameCount == 60)
        precondition(detail.groups[0].minimumGames == 2)
        let rare = detail.groups[0].rareStats[0]
        precondition(rare.name == "Rare" && !rare.qualified && rare.gamesNeeded == 1)
        precondition(detail.groups[0].champions.allSatisfy { $0.qualified && $0.rating != nil })
        precondition(detail.groups[0].mostImproved.allSatisfy { ($0.ratingGain ?? 0) > 0 })
        precondition(!contract.library.champions.isEmpty)
        precondition(contract.library.champions.allSatisfy { $0.seasonId == detail.season.id })
        let player = contract.player.player!
        precondition(player.stats.name == "Rare" && player.games.count == 1)
        precondition(player.games.allSatisfy { ["2025-12-31", "2026-01-02"].contains($0.day) })
        precondition(player.games[0].winnerScore == 21)
        precondition(detail.minimumExplanation == SiteSeasonDraft.minimumExplanation)

        var draft = SiteSeasonDraft(season: detail.season)
        precondition(draft.validationError == nil && draft.automatic)
        precondition(draft.fields["start_date"] as? String == "2025-12-31")
        precondition(draft.fields["end_date"] as? String == "2026-01-02")
        precondition(draft.fields["minimum_games"] == nil)
        draft.automatic = false
        for value in ["0", "-1", "1.5", "", "100001", "many"] {
            draft.minimum = value
            precondition(draft.validationError != nil)
        }
        draft.minimum = "12"
        precondition(draft.validationError == nil)
        precondition(draft.fields["minimum_games"] as? Int == 12)
        precondition(draft.fields["minimum_mode"] as? String == "fixed")
        draft.name = "   "
        precondition(draft.validationError != nil)
        draft.name = "One day"
        draft.startDate = SiteSeasonDraft.date("2024-02-29")!
        draft.endDate = draft.startDate
        precondition(draft.validationError == nil)
        precondition(draft.fields["start_date"] as? String == "2024-02-29")
        draft.endDate = SiteSeasonDraft.date("2024-02-28")!
        precondition(draft.validationError != nil)
        var loads = SiteSeasonLoadGate()
        let first = loads.begin(account: "first account")
        let refreshed = loads.begin(account: "first account")
        precondition(!loads.accepts(first, account: "first account"))
        precondition(loads.accepts(refreshed, account: "first account"))
        precondition(!loads.accepts(refreshed, account: "other account"))
        loads.invalidate() // Saving, sharing, or deleting supersedes an outstanding read.
        precondition(!loads.accepts(refreshed, account: "first account"))
        let signedIn = loads.begin(account: "other account")
        precondition(loads.accepts(signedIn, account: "other account"))
        precondition(!loads.accepts(signedIn, account: nil))
        print("Season API contract, qualification, awards, calendar dates, and form validation passed.")
    }
}
