import Foundation

@main
struct PlayerSuggestionCacheTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = SiteBrowseCache(directory: directory)
        let suggestions = SitePlayerSuggestionCache(cache: disk)
        let key = "account-a-doubles-players"
        var calls = 0
        var finish: CheckedContinuation<[String], Error>?
        let fetch: @MainActor () async throws -> [String] = {
            calls += 1
            return try await withCheckedThrowingContinuation { finish = $0 }
        }

        // Opening Add during preloading shares the request already in flight.
        let preload = Task { try await suggestions.load(key: key, fetch: fetch) }
        while finish == nil { await Task.yield() }
        var formStarted = false
        let form = Task {
            formStarted = true
            return try await suggestions.load(key: key, fetch: fetch)
        }
        while !formStarted { await Task.yield() }
        precondition(calls == 1)
        finish?.resume(returning: ["Recent player", "Another player"])
        let first = try await preload.value
        let second = try await form.value
        precondition(first == second)
        precondition(suggestions.saved(key: key) == first)
        let reused = try await suggestions.load(key: key, fetch: fetch)
        precondition(reused == first && calls == 1)

        // Saved names survive relaunch and are immediately readable even when stale.
        disk.save(first, key: key, generation: disk.generation, now: Date().addingTimeInterval(-120))
        let reopened = SitePlayerSuggestionCache(cache: SiteBrowseCache(directory: directory))
        precondition(reopened.saved(key: key) == first)
        precondition(reopened.saved(key: "account-b-doubles-players").isEmpty)
        enum Offline: Error { case unavailable }
        do {
            _ = try await suggestions.load(key: key) { throw Offline.unavailable }
            preconditionFailure("Expected refresh failure")
        } catch Offline.unavailable { }
        precondition(suggestions.saved(key: key) == first)
        let refreshed = try await suggestions.load(key: key) { ["New player"] }
        precondition(refreshed == ["New player"])

        // A late response cannot restore names cleared by logout or a source change.
        disk.invalidate()
        finish = nil
        let old = Task { try await suggestions.load(key: key, fetch: fetch) }
        while finish == nil { await Task.yield() }
        let oldFinish = finish
        disk.invalidate()
        precondition(suggestions.saved(key: key).isEmpty)
        finish = nil
        let current = Task { try await suggestions.load(key: key, fetch: fetch) }
        while finish == nil { await Task.yield() }
        oldFinish?.resume(returning: ["Removed source"])
        do {
            _ = try await old.value
            preconditionFailure("Expected invalidation to reject the old response")
        } catch is CancellationError { }
        precondition(suggestions.saved(key: key).isEmpty)
        finish?.resume(returning: ["Current source"])
        _ = try await current.value
        precondition(suggestions.saved(key: key) == ["Current source"])
        print("Player suggestions: shared preload, instant reuse, persistence, account isolation, failed refresh, and invalidation passed.")
    }
}
