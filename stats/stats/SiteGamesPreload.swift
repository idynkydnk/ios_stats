import Foundation

struct SiteGamesSelection: Equatable {
    var scope: String
    var section: GameSection
    var year: String
    var division: String
    var otherGame: String
    var search: String = ""

    var cacheKey: String {
        let fields = [scope, section.rawValue, "games-v2", year, division, otherGame, search]
        return (try? JSONEncoder().encode(fields).base64EncodedString()) ?? ""
    }
}

// The foreground page and its preload must read exactly the same snapshot.
struct SiteGamesSnapshot: Codable {
    var doubles: [DoublesGame] = []
    var vollis: [VollisGame] = []
    var other: [OtherGame] = []
    var nextOffset: Int? = nil
    var total: Int? = nil
}

@MainActor
enum SiteGamesPreload {
    static func run(selection: SiteGamesSelection, cache: SiteBrowseCache = .shared,
                    isCurrent: () -> Bool,
                    fetch: (SiteGamesSelection) async throws -> SiteGamesSnapshot) async {
        let generation = cache.generation
        guard !Task.isCancelled, isCurrent() else { return }
        let saved = await cache.loadAsync(SiteGamesSnapshot.self, key: selection.cacheKey)
        guard !Task.isCancelled, isCurrent(), cache.generation == generation,
              saved?.isFresh() != true else { return }
        do {
            let snapshot = try await fetch(selection)
            guard !Task.isCancelled, isCurrent(), cache.generation == generation else { return }
            await cache.saveAsync(snapshot, key: selection.cacheKey, generation: generation)
        } catch {
            // Speculation is silent; opening Games retains its normal retry/error UI.
        }
    }
}
