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
        precondition(saved.isFresh(at: now.addingTimeInterval(59)))
        precondition(!saved.isFresh(at: now.addingTimeInterval(60)))
        precondition(!saved.isFresh(at: now.addingTimeInterval(-1)))
        for otherKey in ["account-b-combined-doubles-2026-open", "public-doubles-2026-open",
                         "account-a-owned-doubles-2026-open", "account-a-combined-doubles-2025-open",
                         "account-a-combined-doubles-2026-women"] {
            precondition(cache.load(DoublesStatsPayload.self, key: otherKey) == nil)
        }
        // Old snapshots are displayable during refresh, but eventually expire.
        cache.save(stats, key: "stale", generation: generation, now: now.addingTimeInterval(-120))
        precondition(cache.load(DoublesStatsPayload.self, key: "stale")?.isFresh() == false)
        cache.save(stats, key: "expired", generation: generation, now: now.addingTimeInterval(-31 * 86400))
        precondition(cache.load(DoublesStatsPayload.self, key: "expired") == nil)
        // Changes/logout remove disk copies and reject late responses.
        cache.invalidate()
        cache.save(stats, key: key, generation: generation)
        precondition(cache.load(DoublesStatsPayload.self, key: key) == nil)
        cache.save(stats, key: key, generation: cache.generation)
        precondition(cache.load(DoublesStatsPayload.self, key: key) != nil)
        // Corrupt data falls back to the server without crashing.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(!files[0].lastPathComponent.contains("account-a"))
        try Data("bad json".utf8).write(to: files[0])
        precondition(cache.load(DoublesStatsPayload.self, key: key) == nil)
        for index in 0..<55 { cache.save([index], key: "item-\(index)", generation: cache.generation) }
        let count = try FileManager.default.contentsOfDirectory(atPath: directory.path).count
        precondition(count <= 48)
        print("Browse cache: persistence, model round trip, freshness, scope isolation, invalidation, late responses, corruption, and size bounds passed.")
    }
}
