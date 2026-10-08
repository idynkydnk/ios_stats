import Foundation

#if os(macOS)
enum SitePublicLink {
    static func absolute(_ value: String?) -> URL? { value.flatMap(URL.init(string:)) }
    static func recap(_ value: String) -> URL? { nil }
}
#endif

@main
struct GameAuthorNameTests {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = Data(#"{"id":1,"updated_by":"google_abc123","updated_by_display_name":"José McDonald"}"#.utf8)
        let game = try decoder.decode(DoublesGame.self, from: payload)
        precondition(game.authorDisplayName() == "José McDonald")
        precondition(game.updatedBy == "google_abc123")
        let saved = try JSONDecoder().decode(DoublesGame.self, from: JSONEncoder().encode(game))
        precondition(saved.authorDisplayName() == "José McDonald")
        let old = try decoder.decode(DoublesGame.self, from: Data(#"{"id":2,"updated_by":"google_abc123"}"#.utf8))
        precondition(old.authorDisplayName(currentUsername: "GOOGLE_ABC123", currentDisplayName: "José McDonald") == "José McDonald")
        precondition(old.authorDisplayName(currentUsername: "another_user", currentDisplayName: "Someone Else") == nil)
        precondition(old.authorDisplayName() == nil)
        var legacy = old
        legacy.updatedBy = "apple_abc123"
        precondition(legacy.authorDisplayName() == nil)
        legacy.updatedBy = "Kyle"
        precondition(legacy.authorDisplayName() == "Kyle")
        legacy.updatedBy = nil
        precondition(legacy.authorDisplayName() == nil)
        print("Game author names: API decoding, saved games, own-account fallback, and social ID suppression passed.")
    }
}
