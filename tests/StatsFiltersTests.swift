import Foundation

@main
struct StatsFiltersTests {
    static func main() {
        let filters = SiteStatsFilters(startDay: "2025-12-31", endDay: "2026-01-02", location: "Beach & Park")
        for root in ["/api/doubles", "/api/vollis", "/api/other"] {
            for path in [root + "/stats", root + "/games", root + "/players/Alex"] {
                let query = filters.apiQuery(path: path, method: "GET", query: ["year": "2026", "offset": "50", "q": "Alex"])
                precondition(query["year"] == "All years")
                precondition(query["start_date"] == "2025-12-31" && query["end_date"] == "2026-01-02")
                precondition(query["location"] == "Beach & Park" && query["offset"] == "50" && query["q"] == "Alex")
            }
        }
        precondition(filters.apiQuery(path: "/api/doubles/games", method: "POST", query: [:]).isEmpty)
        precondition(filters.apiQuery(path: "/api/doubles/games/1", method: "GET", query: [:]).isEmpty)
        precondition(filters.apiQuery(path: "/api/doubles/games", method: "GET", query: ["since": "2026-01-01"]) == ["since": "2026-01-01"])
        precondition(filters.apiQuery(path: "/api/doubles_players", method: "GET", query: [:]).isEmpty)
        let original = URL(string: "https://example.com/stats/All%20years/?division=women&view=signed&location=Old")!
        let shared = filters.applying(to: original)
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: shared, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        precondition(query["division"] == "women" && query["view"] == "signed")
        precondition(query["start_date"] == filters.startDay && query["end_date"] == filters.endDay && query["location"] == filters.location)
        var missing = filters
        missing.missingLocation = true
        precondition(missing.query["missing"] == "1" && missing.query["location"] == nil)
        precondition(filters.cacheKey != missing.cacheKey && filters.cacheKey != SiteStatsFilters().cacheKey)
        let sameDay = SiteStatsFilters(startDay: "2026-10-24", endDay: "2026-10-24")
        precondition(sameDay.hasDates)
        precondition(SiteStatsFilters.day(SiteStatsFilters.date("2026-10-24")!) == "2026-10-24")
        print("Stats filter request, share-link, calendar-day, and cache isolation tests passed.")
    }
}
