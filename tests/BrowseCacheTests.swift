import Foundation

#if os(macOS)
// Recap URL helpers are in a UIKit file; these tests only exercise stats models.
enum SitePublicLink {
    static func absolute(_ value: String?) -> URL? { value.flatMap(URL.init(string:)) }
    static func recap(_ value: String) -> URL? { nil }
}
#endif

@main
struct BrowseCacheTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SiteBrowseCache(directory: directory)
        let generation = cache.generation
        let now = Date()
        let row = RankingRow(name: "Player", wins: 3, losses: 1, winPct: 0.75, rating: 24, plusMinus: 8)
        let stats = DoublesStatsPayload(year: "2026", displayYear: "2026", showingPreviousYear: false,
            minimumGames: 1, allYears: ["2026"], stats: [row], rareStats: [], todayStats: [row], todayGameCount: 4)
        let key = "account-a-combined-doubles-2026-open"
        cache.save(stats, key: key, generation: generation, now: now)
        // A new instance represents reopening the app; real model values survive.
        let reopened = SiteBrowseCache(directory: directory)
        let saved = reopened.load(DoublesStatsPayload.self, key: key)!
        precondition(saved.value.stats[0].rating == 24 && saved.value.todayStats[0].plusMinus == 8)
        precondition(saved.isFresh(at: now.addingTimeInterval(60)))
        precondition(saved.isFresh(at: now.addingTimeInterval(299)))
        precondition(!saved.isFresh(at: now.addingTimeInterval(300)))
        precondition(!saved.isFresh(at: now.addingTimeInterval(-1)))
        for otherKey in ["account-b-combined-doubles-2026-open", "public-doubles-2026-open",
                         "account-a-owned-doubles-2026-open", "account-a-combined-doubles-2025-open",
                         "account-a-combined-doubles-2026-women"] {
            precondition(cache.load(DoublesStatsPayload.self, key: otherKey) == nil)
        }
        // Old snapshots are displayable during refresh, but eventually expire.
        cache.save(stats, key: "stale", generation: generation, now: now.addingTimeInterval(-360))
        precondition(cache.load(DoublesStatsPayload.self, key: "stale")?.isFresh() == false)
        cache.save(stats, key: "expired", generation: generation, now: now.addingTimeInterval(-31 * 86400))
        precondition(cache.load(DoublesStatsPayload.self, key: "expired") == nil)
        // Game changes preserve readable results across relaunch, but force a fetch.
        let refreshNotification = DispatchSemaphore(value: 0)
        let observer = NotificationCenter.default.addObserver(forName: SiteBrowseCache.didChange, object: cache, queue: nil) { _ in
            refreshNotification.signal()
        }
        cache.markStale()
        NotificationCenter.default.removeObserver(observer)
        precondition(refreshNotification.wait(timeout: .now()) == .success)
        let changed = SiteBrowseCache(directory: directory).load(DoublesStatsPayload.self, key: key)!
        precondition(changed.value.stats[0].rating == 24 && !changed.isFresh())
        cache.save(["Late response"], key: "late", generation: generation)
        precondition(cache.load([String].self, key: "late") == nil)
        cache.save(stats, key: key, generation: cache.generation)
        precondition(cache.load(DoublesStatsPayload.self, key: key)?.isFresh() == true)
        // Changes to a separate player cache cannot discard or stale standings.
        let players = SiteBrowseCache(directory: directory.appendingPathComponent("players"))
        players.save(["New player"], key: "names", generation: players.generation)
        players.invalidate()
        precondition(cache.load(DoublesStatsPayload.self, key: key)?.isFresh() == true)
        // Logout/source changes remove disk copies and reject late responses.
        cache.invalidate()
        cache.save(stats, key: key, generation: generation)
        precondition(cache.load(DoublesStatsPayload.self, key: key) == nil)
        cache.save(stats, key: key, generation: cache.generation)
        precondition(cache.load(DoublesStatsPayload.self, key: key) != nil)
        // Paged player snapshots preserve totals/cursors and every browsing scope.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let player = try decoder.decode(DoublesPlayerPayload.self, from: Data("""
            {"name":"Player","year":"2026","all_years":["2026"],"games":[],
             "games_total":65,"games_next_offset":30,"rating":24,"nickname":"P"}
            """.utf8))
        let playerKey = SiteBrowseCache.playerKey(scope: "account-a", section: "doubles", year: "2026", name: "Player", division: "open", revision: 1)
        cache.save(player, key: playerKey, generation: cache.generation)
        let restored = cache.load(DoublesPlayerPayload.self, key: playerKey)!.value
        precondition(restored.gamesTotal == 65 && restored.gamesNextOffset == 30 && restored.nickname == "P")
        for (scope, section, year, name, division, revision) in [
            ("account-b", "doubles", "2026", "Player", "open", 1),
            ("account-a", "doubles", "2025", "Player", "open", 1),
            ("account-a", "vollis", "2026", "Player", "open", 1),
            ("account-a", "doubles", "2026", "Another player", "open", 1),
            ("account-a", "doubles", "2026", "Player", "women", 1),
            ("account-a", "doubles", "2026", "Player", "open", 2)
        ] {
            let different = SiteBrowseCache.playerKey(scope: scope, section: section, year: year, name: name, division: division, revision: revision)
            precondition(different != playerKey && cache.load(DoublesPlayerPayload.self, key: different) == nil)
        }
        let oldServer = try decoder.decode(DoublesPlayerPayload.self, from: Data("{\"name\":\"Player\",\"games\":[]}".utf8))
        precondition(oldServer.gamesTotal == nil && oldServer.gamesNextOffset == nil)
        for path in ["/api/update_player_info", "/api/player_photo/Player/", "/api/rename_player", "/api/doubles/games"] {
            precondition(SiteStatsRefreshPolicy.affectsPlayerDetails(method: "POST", path: path))
            precondition(!SiteStatsRefreshPolicy.affectsPlayerDetails(method: "GET", path: path))
        }
        precondition(!SiteStatsRefreshPolicy.affectsPlayerDetails(method: "POST", path: "/api/ai/summary"))
        cache.invalidate()
        cache.save(stats, key: key, generation: cache.generation)
        // Corrupt data falls back to the server without crashing.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(!files[0].lastPathComponent.contains("account-a"))
        try Data("bad json".utf8).write(to: files[0])
        precondition(cache.load(DoublesStatsPayload.self, key: key) == nil)
        for index in 0..<55 { cache.save([index], key: "item-\(index)", generation: cache.generation) }
        let count = try FileManager.default.contentsOfDirectory(atPath: directory.path).count
        precondition(count <= 48)
        for kind in ["doubles", "vollis", "other"] {
            for (method, suffix) in [("POST", ""), ("PUT", "/42"), ("DELETE", "/42")] {
                precondition(SiteStatsRefreshPolicy.affectsStats(method: method, path: "/api/\(kind)/games\(suffix)"))
            }
            precondition(!SiteStatsRefreshPolicy.affectsStats(method: "GET", path: "/api/\(kind)/games"))
        }
        for path in ["/api/rename_player", "/api/admin/undo/42", "/api/admin/clear_cache"] {
            precondition(SiteStatsRefreshPolicy.affectsStats(method: "POST", path: path))
        }
        for path in ["/api/ai/summary", "/api/ai/roster", "/api/flyers/42", "/api/update_player_info",
                     "/api/add_player", "/api/account/display-name", "/api/auth/apple/challenge",
                     "/api/admin/backup", "/api/admin/test_email", "/api/admin/users/reset_password",
                     "/api/doubles/games/search"] {
            for method in ["POST", "PUT", "DELETE"] {
                precondition(!SiteStatsRefreshPolicy.affectsStats(method: method, path: path))
            }
        }
        precondition(SiteStatsRefreshPolicy.affectsPlayerSuggestions(method: "POST", path: "/api/add_player"))
        precondition(!SiteStatsRefreshPolicy.affectsPlayerSuggestions(method: "POST", path: "/api/ai/roster"))
        print("Browse cache: five-minute freshness, preserved stale results, separate player cache, mutation policy, persistence, scope isolation, late responses, corruption, and size bounds passed.")
    }
}
