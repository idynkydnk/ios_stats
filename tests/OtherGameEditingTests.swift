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
        print("Other game editing checks passed")
    }
}
