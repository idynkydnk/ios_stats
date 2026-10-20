import Foundation

#if os(macOS)
enum SitePublicLink {
    static func absolute(_ value: String?) -> URL? { value.flatMap(URL.init(string:)) }
    static func recap(_ value: String) -> URL? { nil }
}
#endif

@main
struct OneOnOneTests {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"games":[{"id":1,"source_id":1,"source":"vollis","game_name":"Vollis","winner":"A","loser":"B","winner_score":21,"loser_score":15,"can_edit":false},{"id":-1,"source_id":1,"source":"other","game_name":"Short court two boxes","winner":"B","loser":"A","winner_score":11,"loser_score":0,"can_edit":true,"other_game":{"id":1,"game_name":"Short court two boxes","game_type":"Volleyball","winners":[{"name":"B","score":11}],"losers":[{"name":"A","score":0}],"comment":"Original comment"}}],"total":2,"next_offset":null}"#
        let payload = try decoder.decode(GamesListPayload<VollisGame>.self, from: Data(json.utf8))
        precondition(Set(payload.games.map(\.id)).count == 2, "Records from different stores must not collide")
        let boxes = payload.games[1]
        precondition(boxes.sourceId == 1 && boxes.id == -1 && boxes.canEdit == true)
        precondition(boxes.otherGame?.id == 1 && boxes.otherGame?.editingScoreType == "individual")
        precondition(boxes.otherGame?.comment == "Original comment")
        precondition(boxes.otherGame?.losers?.first?.score == 0)
        let restored = try JSONDecoder().decode(VollisGame.self, from: JSONEncoder().encode(boxes))
        precondition(restored == boxes, "Saved game data must preserve the original edit target")
        let rows = RankingRow.todayStats(fromVollis: payload.games)
        precondition(rows.allSatisfy { $0.wins == 1 && $0.losses == 1 })
        let history = try decoder.decode(DoublesPlayerPayload.self, from: Data(#"{"name":"A","year":"All years","all_years":["2026"],"games":[{"id":-1,"game_name":"Italian short court","winner1":"B","loser1":"A","winner_score":21,"loser_score":15}]}"#.utf8))
        precondition(history.games?.first?.gameName == "Italian short court")
        precondition(history.games?.first?.winner1 == "B")
        precondition(GameSection.vollis.title == "1v1")
        print("1v1 models: source identity, editing data, saved games, combined totals, and history passed")
    }
}
