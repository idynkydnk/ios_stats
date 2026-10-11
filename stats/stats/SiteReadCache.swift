import Foundation

/// Scoped metadata reuse plus one fetch shared by concurrent consumers.
@MainActor
final class SiteReadCache<Value: Codable & Sendable> {
    private let cache: SiteBrowseCache
    private var pending: [String: (id: UUID, generation: UUID, task: Task<Value, Error>)] = [:]

    init(cache: SiteBrowseCache) { self.cache = cache }

    func load(key: String, maxAge: TimeInterval = 300,
              fetch: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let generation = cache.generation
        if let saved = await cache.loadAsync(Value.self, key: key), saved.isFresh(maxAge: maxAge) {
            guard cache.generation == generation else { throw CancellationError() }
            try Task.checkCancellation()
            return saved.value
        }
        guard cache.generation == generation else { throw CancellationError() }
        let request: (id: UUID, generation: UUID, task: Task<Value, Error>)
        if let existing = pending[key], existing.generation == generation {
            request = existing
        } else {
            request = (UUID(), generation, Task {
                let value = try await fetch()
                guard self.cache.generation == generation else { throw CancellationError() }
                await self.cache.saveAsync(value, key: key, generation: generation)
                return value
            })
            pending[key] = request
        }
        defer { if pending[key]?.id == request.id { pending[key] = nil } }
        let value = try await request.task.value
        guard cache.generation == generation else { throw CancellationError() }
        try Task.checkCancellation()
        return value
    }
}

/// Coalesce only simultaneous GETs. Results are not retained here, and writes
/// never enter this path. One canceled screen cannot cancel another's request.
@MainActor
final class SiteGETRequests {
    private var pending: [String: (id: UUID, task: Task<(Data, URLResponse), Error>)] = [:]

    static func key(_ request: URLRequest, revision: String = "") -> String {
        let fields = [request.httpMethod ?? "GET", request.url?.absoluteString ?? "", revision]
            + (request.allHTTPHeaderFields ?? [:]).map { $0.key.lowercased() + ":" + $0.value }.sorted()
        return (try? JSONEncoder().encode(fields).base64EncodedString()) ?? ""
    }

    func load(key: String, fetch: @escaping @MainActor () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let request: (id: UUID, task: Task<(Data, URLResponse), Error>)
        if let existing = pending[key] { request = existing }
        else {
            request = (UUID(), Task { try await fetch() })
            pending[key] = request
        }
        defer { if pending[key]?.id == request.id { pending[key] = nil } }
        let value = try await request.task.value
        try Task.checkCancellation()
        return value
    }
}
