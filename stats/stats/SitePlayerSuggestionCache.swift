import Foundation

/// Share preloading and form requests, while keeping saved names available during refresh.
@MainActor
final class SitePlayerSuggestionCache {
    static let shared = SitePlayerSuggestionCache(cache: .shared)

    private let cache: SiteBrowseCache
    private var pending: [String: (id: UUID, generation: UUID, task: Task<[String], Error>)] = [:]

    init(cache: SiteBrowseCache) {
        self.cache = cache
    }

    func saved(key: String) -> [String] {
        cache.load([String].self, key: key)?.value ?? []
    }

    func load(key: String, fetch: @escaping @MainActor () async throws -> [String]) async throws -> [String] {
        if let saved = cache.load([String].self, key: key), saved.isFresh() {
            return saved.value
        }
        let generation = cache.generation
        let request: (id: UUID, generation: UUID, task: Task<[String], Error>)
        if let existing = pending[key], existing.generation == generation {
            request = existing
        } else {
            request = (UUID(), generation, Task { try await fetch() })
            pending[key] = request
        }
        defer {
            if pending[key]?.id == request.id { pending[key] = nil }
        }
        let names = try await request.task.value
        // A save, source change, or logout can invalidate an in-flight request.
        guard cache.generation == generation else { throw CancellationError() }
        cache.save(names, key: key, generation: generation)
        return names
    }
}
