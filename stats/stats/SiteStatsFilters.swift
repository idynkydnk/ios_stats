import Foundation

/// Date-only values stay the same on devices in different time zones.
nonisolated struct SiteStatsFilters: Codable, Equatable, Sendable {
    var startDay = ""
    var endDay = ""
    var location = ""
    var missingLocation = false

    var hasDates: Bool { !startDay.isEmpty && !endDay.isEmpty }
    var isActive: Bool { hasDates || !location.isEmpty || missingLocation }
    var cacheKey: String { (try? JSONEncoder().encode(self).base64EncodedString()) ?? "" }
    var query: [String: String] {
        var values: [String: String] = [:]
        if hasDates { values["start_date"] = startDay; values["end_date"] = endDay }
        if missingLocation { values["missing"] = "1" }
        else if !location.isEmpty { values["location"] = location }
        return values
    }
    var summary: String {
        var parts: [String] = []
        if hasDates { parts.append("\(startDay) through \(endDay)") }
        if missingLocation { parts.append("No location yet") }
        else if !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }
    func applying(to url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (parts.queryItems ?? []).filter { !["start_date", "end_date", "location", "missing"].contains($0.name) }
        items += query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        parts.queryItems = items.isEmpty ? nil : items
        return parts.url ?? url
    }
    func apiQuery(path: String, method: String, query: [String: String]) -> [String: String] {
        let roots = ["/api/doubles", "/api/vollis", "/api/other"]
        let browse = path == "/api/volleyball/stats" || roots.contains { root in
            path == root + "/stats" || path == root + "/games" || path.hasPrefix(root + "/players/")
        }
        guard method == "GET", browse, query["since"] == nil else { return query }
        var values = query.merging(self.query) { _, new in new }
        if hasDates { values["year"] = "All years" }
        return values
    }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func date(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: day)
    }
}
