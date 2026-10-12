import Foundation

#if os(macOS)
enum SitePublicLink {
    static func absolute(_ value: String?) -> URL? { value.flatMap(URL.init(string:)) }
    static func recap(_ value: String) -> URL? { nil }
}
#endif

@main
struct GamesPreloadTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SiteBrowseCache(directory: directory)
        let selection = SiteGamesSelection(scope: "account-a", section: .doubles, year: "2026", division: "open", otherGame: "")
        var calls = 0
        let fetch: (SiteGamesSelection) async throws -> SiteGamesSnapshot = { received in
            precondition(received == selection)
            calls += 1
            return SiteGamesSnapshot(nextOffset: 50, total: 896)
        }
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { true }, fetch: fetch)
        let saved = await cache.loadAsync(SiteGamesSnapshot.self, key: selection.cacheKey)
        precondition(saved?.value.nextOffset == 50 && saved?.value.total == 896)
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { true }, fetch: fetch)
        precondition(calls == 1, "Fresh pages must not download again")
        // Existing on-disk Games snapshots keep their keys across this change.
        let oldFields = ["account-a", "doubles", "games-v2", "2026", "open", "", ""]
        precondition(selection.cacheKey == (try! JSONEncoder().encode(oldFields)).base64EncodedString())
        var alternatives: [SiteGamesSelection] = []
        var changed = selection; changed.scope = "account-b"; alternatives.append(changed)
        changed = selection; changed.section = .vollis; alternatives.append(changed)
        changed = selection; changed.year = "2025"; alternatives.append(changed)
        changed = selection; changed.division = "women"; alternatives.append(changed)
        changed = selection; changed.otherGame = "No jump"; alternatives.append(changed)
        changed = selection; changed.search = "Player"; alternatives.append(changed)
        for other in alternatives {
            precondition(other.cacheKey != selection.cacheKey)
            precondition(cache.load(SiteGamesSnapshot.self, key: other.cacheKey) == nil)
        }
        cache.markStale(section: "doubles")
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { true }, fetch: fetch)
        precondition(calls == 2, "Game edits must allow a new preload")

        // A changed selection before starting must do no network work.
        cache.invalidate()
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { false }, fetch: fetch)
        precondition(calls == 2)
        // A source change or mutation during the request rejects the late result.
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { true }) { _ in
            cache.invalidate()
            return SiteGamesSnapshot(total: 999)
        }
        precondition(cache.load(SiteGamesSnapshot.self, key: selection.cacheKey) == nil)
        var current = true
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { current }) { _ in
            current = false
            return SiteGamesSnapshot(total: 999)
        }
        precondition(cache.load(SiteGamesSnapshot.self, key: selection.cacheKey) == nil)

        var finish: CheckedContinuation<SiteGamesSnapshot, Never>?
        let canceled = Task {
            await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { true }) { _ in
                await withCheckedContinuation { finish = $0 }
            }
        }
        while finish == nil { await Task.yield() }
        canceled.cancel()
        finish!.resume(returning: SiteGamesSnapshot(total: 999))
        await canceled.value
        precondition(cache.load(SiteGamesSnapshot.self, key: selection.cacheKey) == nil)
        enum Failure: Error { case expected }
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { true }) { _ in throw Failure.expected }
        await SiteGamesPreload.run(selection: selection, cache: cache, isCurrent: { true }, fetch: fetch)
        precondition(calls == 3, "Preload failures must permit a retry")
        print("Games preload: reuse, pagination, scope isolation, invalidation, cancellation and retries passed.")
    }
}
