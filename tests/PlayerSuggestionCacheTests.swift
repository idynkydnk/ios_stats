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
            let names: [String] = try await withCheckedThrowingContinuation { finish = $0 }
            try Task.checkCancellation()
            return names
        }

        // Leaving the preloading screen must not cancel the shared request Add needs.
        let preload = Task { try await suggestions.load(key: key, fetch: fetch) }
        while finish == nil { await Task.yield() }
        preload.cancel()
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

        // Saving a game or restoring a verified session keeps old names readable
        // immediately, including after relaunch, while a slow refresh is pending.
        disk.markStale()
        precondition(suggestions.saved(key: key) == refreshed)
        let afterMutation = SiteBrowseCache(directory: directory)
        let staleEntry = afterMutation.load([String].self, key: key)
        precondition(staleEntry?.value == refreshed && staleEntry?.isFresh() == false)
        finish = nil
        let beforeNextSave = Task { try await suggestions.load(key: key, fetch: fetch) }
        while finish == nil { await Task.yield() }
        let beforeNextSaveFinish = finish
        precondition(suggestions.saved(key: key) == refreshed)

        // Another save during that refresh rejects its late result, without
        // clearing usable names or letting it replace the newer request.
        disk.markStale()
        finish = nil
        let afterNextSave = Task { try await suggestions.load(key: key, fetch: fetch) }
        while finish == nil { await Task.yield() }
        precondition(suggestions.saved(key: key) == refreshed)
        beforeNextSaveFinish?.resume(returning: ["Outdated order"])
        do {
            _ = try await beforeNextSave.value
            preconditionFailure("Expected a save to reject the older response")
        } catch is CancellationError { }
        precondition(suggestions.saved(key: key) == refreshed)
        finish?.resume(returning: ["Latest player", "New player"])
        let latest = try await afterNextSave.value
        precondition(suggestions.saved(key: key) == latest)

        // Other games have separate lists: loading a second game cannot reuse
        // either Doubles or the first game's saved names or in-flight request.
        let noJumpKey = "account-a-other-no-jump-players"
        let sequenceKey = "account-a-other-sequence-players"
        finish = nil
        let noJump = Task { try await suggestions.load(key: noJumpKey, fetch: fetch) }
        while finish == nil { await Task.yield() }
        precondition(suggestions.saved(key: noJumpKey).isEmpty)
        let sequence = try await suggestions.load(key: sequenceKey) { ["Sequence player"] }
        precondition(sequence == ["Sequence player"])
        precondition(suggestions.saved(key: noJumpKey).isEmpty)
        precondition(suggestions.saved(key: key) == latest)
        finish?.resume(returning: ["No jump player"])
        _ = try await noJump.value
        precondition(suggestions.saved(key: noJumpKey) == ["No jump player"])
        precondition(suggestions.saved(key: sequenceKey) == sequence)
        precondition(suggestions.saved(key: "account-b-other-no-jump-players").isEmpty)

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
        print("Player suggestions: canceled preload sharing, instant stale reuse, persistence, per-game/account isolation, failed refresh, mutation races, and invalidation passed.")
    }
}
