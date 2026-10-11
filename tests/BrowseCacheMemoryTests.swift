import Foundation

@main
struct BrowseCacheMemoryTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SiteBrowseCache(directory: directory, maxMemoryEntries: 2, maxMemoryBytes: 4096)
        func files() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        }
        func snapshot() throws -> [URL: Data] {
            try Dictionary(uniqueKeysWithValues: files().map { ($0, try Data(contentsOf: $0)) })
        }
        cache.save(["Doubles"], key: "account-doubles-2026", generation: cache.generation)
        cache.save(["Vollis"], key: "account-vollis-2026", generation: cache.generation)
        let before = try snapshot()
        let modified = try files().map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        cache.markStale(section: "vollis")
        let after = try snapshot()
        let afterModified = try files().map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        precondition(before == after && modified == afterModified, "Invalidation rewrote snapshots")
        let reopened = SiteBrowseCache(directory: directory)
        precondition(reopened.load([String].self, key: "account-doubles-2026")!.isFresh())
        precondition(!reopened.load([String].self, key: "account-vollis-2026")!.isFresh())
        // A corrupt marker must fail stale even with otherwise valid snapshots.
        try Data("broken".utf8).write(to: directory.appendingPathComponent(".revisions"))
        precondition(!SiteBrowseCache(directory: directory).load([String].self, key: "account-doubles-2026")!.isFresh())

        cache.invalidate()
        cache.save(["A"], key: "a", generation: cache.generation)
        cache.save(["B"], key: "b", generation: cache.generation)
        precondition(cache.load([String].self, key: "a")!.value == ["A"])
        cache.save(["C"], key: "c", generation: cache.generation)
        // Destroy disk to distinguish a decoded hit from rereading JSON.
        for file in try files() { try Data("broken".utf8).write(to: file) }
        precondition(cache.load([String].self, key: "a")!.value == ["A"])
        precondition(cache.load([String].self, key: "b") == nil, "Least recently used entry wasn't evicted")
        precondition(cache.load([String].self, key: "c")!.value == ["C"])
        cache.trimMemory()
        precondition(cache.load([String].self, key: "a") == nil)
        // An oversized replacement cannot leave an older decoded value visible.
        cache.save(["small"], key: "size", generation: cache.generation)
        let big = [String(repeating: "x", count: 2048)]
        cache.save(big, key: "size", generation: cache.generation)
        precondition(cache.load([String].self, key: "size")!.value == big)
        // Legacy entries without revision fields remain readable and turn stale.
        cache.invalidate()
        cache.save(["legacy"], key: "legacy", generation: cache.generation)
        let file = try files()[0]
        try Data("{\"value\":[\"legacy\"],\"savedAt\":\(Date().timeIntervalSinceReferenceDate)}".utf8).write(to: file)
        cache.markStale(section: "doubles")
        let legacy = SiteBrowseCache(directory: directory).load([String].self, key: "legacy")!
        precondition(legacy.value == ["legacy"] && !legacy.isFresh())
        print("Browse memory: decoded reuse, LRU, memory pressure, size bounds, legacy data and durable constant-write invalidation passed.")
    }
}
