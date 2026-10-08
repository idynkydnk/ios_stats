import Foundation

enum SiteStatsRefreshPolicy {
    static func affectsStats(method: String, path: String) -> Bool {
        guard ["POST", "PUT", "DELETE"].contains(method) else { return false }
        let parts = path.split(separator: "/")
        if parts.count >= 3, parts[0] == "api",
           ["doubles", "vollis", "other"].contains(String(parts[1])), parts[2] == "games" {
            return parts.count == 3 || (parts.count == 4 && Int(parts[3]) != nil)
        }
        // These actions can change recorded results or the names in standings.
        return path == "/api/rename_player" || path == "/api/admin/clear_cache"
            || (parts.count == 4 && parts.prefix(3) == ["api", "admin", "undo"] && Int(parts[3]) != nil)
    }

    static func affectsPlayerSuggestions(method: String, path: String) -> Bool {
        affectsStats(method: method, path: path)
            || (method == "POST" && ["/api/add_player", "/api/update_player_info"].contains(path))
    }
}
