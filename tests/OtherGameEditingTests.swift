import Foundation

// SiteModels also contains recap links, unrelated to these standalone model checks.
#if os(macOS)
enum SitePublicLink {
    static func absolute(_ value: String?) -> URL? { value.flatMap(URL.init(string:)) }
    static func recap(_ value: String) -> URL? { nil }
}
#endif

@main
struct OtherGameEditingTests {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func game(_ json: String) throws -> OtherGame {
            try decoder.decode(OtherGame.self, from: Data(json.utf8))
        }

        // Aggregate scores also accompany individual results; retain each player's score.
        let individual = try game(#"{"id":7,"winner_score":12,"loser_score":0,"winners":[{"name":"A","score":12},{"name":"B","score":"9"}],"losers":[{"name":"C","score":0}]}"#)
        precondition(individual.editingScoreType == "individual")
        precondition(individual.displayWinners == ["A", "B"])
        precondition(individual.winners?.map(\.score) == [12, 9])
        precondition(individual.losers?.first?.score == 0)

        let team = try game(#"{"id":8,"winner_score":21,"loser_score":0,"winners":[{"name":"A","score":null}],"losers":[{"name":"B","score":null}]}"#)
        precondition(team.editingScoreType == "team")
        precondition(team.loserScore == 0)

        let unscored = try game(#"{"id":9,"winners":["A","B"],"losers":["C"],"comment":"Close game","location":"Beach"}"#)
        precondition(unscored.editingScoreType == "none")
        precondition(unscored.displayWinners == ["A", "B"])
        precondition(unscored.comment == "Close game" && unscored.location == "Beach")

        let legacy = try game(#"{"game_id":10,"winner1":"A","winner2":"B","loser1":"C","winner_score":"5","loser_score":"3"}"#)
        precondition(legacy.id == 10 && legacy.editingScoreType == "team")
        precondition(legacy.displayWinners == ["A", "B"])
        precondition(!legacy.isTie && !individual.isTie, "Old results must retain their recorded outcome")
        let tie = try game(#"{"id":11,"game_name":"Sequence","is_tie":true,"winner_score":1,"loser_score":1,"winners":[{"name":"A"}],"losers":[{"name":"B"}]}"#)
        precondition(tie.isTie && tie.editingScoreType == "team")
        precondition(tie.winnerScore == 1 && tie.loserScore == 1)
        precondition(tie.displayWinners == ["A"] && tie.displayLosers == ["B"])
        let restored = try JSONDecoder().decode(OtherGame.self, from: JSONEncoder().encode(tie))
        precondition(restored == tie, "Saved games retain tie status when reopened for editing")
        let numericTie = try game(#"{"id":12,"is_tie":1}"#)
        precondition(numericTie.isTie)
        let historicalEqualScores = try game(#"{"id":13,"winner_score":1,"loser_score":1}"#)
        precondition(!historicalEqualScores.isTie,
                     "Matching scores alone must not rewrite historical outcomes")
        let ranking = try decoder.decode(RankingRow.self, from: Data(#"{"name":"A","wins":2,"losses":1,"ties":3,"win_pct":0.333333}"#.utf8))
        precondition(ranking.ties == 3 && ranking.gamesCount == 6)
        let opponent = try decoder.decode(MatchupRow.self, from: Data(#"{"opponent":"B","wins":0,"losses":0,"ties":1,"win_percentage":0,"total_games":1}"#.utf8))
        precondition(opponent.ties == 1 && opponent.totalGames == 1)
        precondition(OtherGame.allowsTie(gameType: "Board game", gameName: "Sequence"))
        precondition(OtherGame.allowsTie(gameType: "Card game", gameName: "Euchre"))
        precondition(!OtherGame.allowsTie(gameType: "Volleyball", gameName: "No jump"))
        precondition(!OtherGame.allowsTie(gameType: " beach VOLLEYBALL ", gameName: "Coed"))
        precondition(!OtherGame.allowsTie(gameType: "Other", gameName: " vollis "))
        precondition(!OtherGame.allowsTie(gameType: "Other", gameName: "Short court", oneOnOne: true))
        print("Other game editing and tie checks passed")
    }
}
