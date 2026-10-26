import Foundation

enum SitePublicLink {
    static func absolute(_ value: String?) -> URL? { value.flatMap(URL.init(string:)) }
    static func recap(_ value: String) -> URL? { nil }
}
@MainActor final class SiteAuthManager {
    static let shared = SiteAuthManager()
    var username: String? = "alice"
    var token: String? = "alice-token"
    var isLoggedIn = true
    var sessionReady = true
    var isPreviewing = false
}
@MainActor final class NetworkMonitor {
    static let shared = NetworkMonitor()
    var isConnected = false
}
@MainActor final class SiteBrowseCache {
    static let shared = SiteBrowseCache()
    static let playerDetails = SiteBrowseCache()
    static let navigation = SiteBrowseCache()
    static let playerSuggestions = SiteBrowseCache()
    var invalidations = 0
    func markStale() { invalidations += 1 }
}
@MainActor final class PythonAnywhereClient {
    static let shared = PythonAnywhereClient()
    var receiptIDs: [String: Int] = [:]
    var attempts = 0
    var inFlight = 0
    var maximumInFlight = 0
    var loseFirstResponse = false
    var rejection: Int? = nil
    var capabilityAvailable = true
    var onUpload: ((SiteLocalGame) async -> Void)?
    func requireLocalGameSync() async throws {
        if !capabilityAvailable { throw URLError(.badServerResponse) }
    }
    func syncLocalGame(_ game: SiteLocalGame) async throws -> Int {
        attempts += 1
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        if let rejection { throw SiteAPIError.http(rejection, "Rejected") }
        if let onUpload { await onUpload(game) }
        let id = receiptIDs[game.id] ?? receiptIDs.count + 1
        receiptIDs[game.id] = id
        if loseFirstResponse { loseFirstResponse = false; throw URLError(.networkConnectionLost) }
        return id
    }
}

@main struct LocalGameSyncTests {
    @MainActor static func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Sync condition did not complete")
    }
    @MainActor static func main() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("games.json")
        let store = SiteLocalGameStore(url: file)
        let fields: [String: Any] = ["winner1": "A", "winner2": "B", "loser1": "C", "loser2": "D", "winner_score": 21, "loser_score": 15, "game_date": "2026-10-26 12:34:56"]
        try store.save(kind: "doubles", fields: fields)
        try store.save(kind: "doubles", fields: fields)
        precondition(store.pending.count == 2 && PythonAnywhereClient.shared.attempts == 0)
        let restored = SiteLocalGameStore(url: file)
        restored.selectAccount("alice")
        precondition(restored.pending.count == 2)
        NetworkMonitor.shared.isConnected = true
        PythonAnywhereClient.shared.loseFirstResponse = true
        for _ in 0..<10 { restored.startSync() }
        try await eventually { restored.pending.isEmpty && !restored.syncing }
        precondition(PythonAnywhereClient.shared.receiptIDs.count == 2)
        precondition(PythonAnywhereClient.shared.attempts == 3 && PythonAnywhereClient.shared.maximumInFlight == 1)
        let saved = try SiteLocalGameLedger(url: file)
        precondition(saved.games.allSatisfy { $0.serverID != nil })
        // A validation failure stays durable, visible, and is not retried forever.
        PythonAnywhereClient.shared.rejection = 422
        try restored.save(kind: "doubles", fields: fields)
        try await eventually { restored.pending.first?.needsAttention == true }
        let attempts = PythonAnywhereClient.shared.attempts
        restored.startSync()
        try await Task.sleep(for: .milliseconds(50))
        precondition(PythonAnywhereClient.shared.attempts == attempts)
        PythonAnywhereClient.shared.rejection = nil
        restored.retry()
        try await eventually { restored.pending.isEmpty }
        // An upload finishing after account switching still belongs to its owner.
        var release: CheckedContinuation<Void, Never>?
        PythonAnywhereClient.shared.onUpload = { game in
            if game.owner == "alice" { await withCheckedContinuation { release = $0 } }
        }
        try restored.save(kind: "doubles", fields: fields)
        try await eventually { release != nil }
        SiteAuthManager.shared.username = "bob"; SiteAuthManager.shared.token = "bob-token"
        restored.selectAccount("bob")
        precondition(restored.games.isEmpty)
        try restored.save(kind: "doubles", fields: fields)
        try await eventually { restored.pending.isEmpty }
        release?.resume()
        try await Task.sleep(for: .milliseconds(30))
        precondition(restored.games.count == 1 && restored.games[0].owner == "bob")
        let ledger = try SiteLocalGameLedger(url: file)
        precondition(ledger.games.filter { $0.owner == "alice" }.allSatisfy { $0.serverID != nil })
        print("Offline queue, restart, lost-response retry, single worker, validation failures, and account-switch sync checks passed")
    }
}
