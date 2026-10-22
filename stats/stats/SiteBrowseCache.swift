import Foundation
import CryptoKit

/// Disposable, account-scoped snapshots. The server remains authoritative.
nonisolated final class SiteBrowseCache: @unchecked Sendable {
    static let shared = SiteBrowseCache()
    static let playerSuggestions = SiteBrowseCache(directory: cacheDirectory("StatsPlayers-v1"))
    // Older snapshots could contain personal fields now redacted on shared profiles.
    static let playerDetails = SiteBrowseCache(directory: cacheDirectory("StatsPlayerDetails-v2"))
    static let library = SiteBrowseCache(directory: cacheDirectory("StatsLibrary-v1"))
    static let navigation = SiteBrowseCache(directory: cacheDirectory("StatsNavigation-v1"))

    private static func cacheDirectory(_ name: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }

    static func playerKey(scope: String, section: String, year: String, name: String, division: String, revision: Int) -> String {
        let fields = [scope, section, year, name, division, String(revision)]
        return (try? JSONEncoder().encode(fields).base64EncodedString()) ?? ""
    }

    func loadAsync<Value: Codable>(_ type: Value.Type, key: String) async -> Entry<Value>? {
        // Most returns to a screen need neither disk I/O nor JSON decoding.
        if let entry = memoryEntry(type, key: key) { return entry }
        return await Task.detached(priority: .userInitiated) { self.load(type, key: key) }.value
    }

    func saveAsync<Value: Codable>(_ value: Value, key: String, generation: UUID) async {
        await Task.detached(priority: .utility) { self.save(value, key: key, generation: generation) }.value
    }

    static let didChange = Notification.Name("SiteBrowseCache.didChange")
    struct Entry<Value: Codable>: Codable {
        var value: Value
        var savedAt: Date
        var refreshRequired: Bool? = nil
        var section: String? = nil
        var globalRevision: UUID? = nil
        var sectionRevision: UUID? = nil

        func isFresh(at now: Date = Date(), maxAge: TimeInterval = 5 * 60) -> Bool {
            let age = now.timeIntervalSince(savedAt)
            return refreshRequired != true && age >= 0 && age < maxAge
        }
    }

    private struct Revisions: Codable {
        var all: UUID? = nil
        var unknown: UUID? = nil
        var sections: [String: UUID] = [:]
    }
    private struct MemoryEntry {
        var value: Any
        var cost: Int
        var access: UInt64
    }
    private let directory: URL
    private let lock = NSLock()
    private var revision = UUID()
    private var revisions = Revisions()
    private var revisionsDirty = false
    private var memory: [String: MemoryEntry] = [:]
    private var memoryBytes = 0
    private var clock: UInt64 = 0
    private let maxMemoryEntries: Int
    private let maxMemoryBytes: Int
    private let maxEntries = 48
    private var diskEntries: [String: Date]?

    init(directory: URL = cacheDirectory("StatsBrowse-v1"), maxMemoryEntries: Int = 12,
         maxMemoryBytes: Int = 16 * 1024 * 1024) {
        self.directory = directory
        self.maxMemoryEntries = maxMemoryEntries
        self.maxMemoryBytes = maxMemoryBytes
        let marker = directory.appendingPathComponent(".revisions")
        if FileManager.default.fileExists(atPath: marker.path) {
            // Corrupt revision metadata must never make an old snapshot fresh.
            revisions = (try? JSONDecoder().decode(Revisions.self, from: Data(contentsOf: marker)))
                ?? Revisions(all: UUID())
            revisionsDirty = true
        }
    }

    var generation: UUID {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    private func refreshed<Value>(_ entry: Entry<Value>) -> Entry<Value>? {
        guard Date().timeIntervalSince(entry.savedAt) < 30 * 24 * 60 * 60 else { return nil }
        var result = entry
        let currentSection = entry.section.map { revisions.sections[$0] } ?? revisions.unknown
        if entry.globalRevision != revisions.all || entry.sectionRevision != currentSection {
            result.refreshRequired = true
        }
        return result
    }

    private func memoryEntry<Value: Codable>(_ type: Value.Type, key: String) -> Entry<Value>? {
        lock.lock()
        defer { lock.unlock() }
        return memoryEntryLocked(type, key: key)
    }

    private func memoryEntryLocked<Value: Codable>(_ type: Value.Type, key: String) -> Entry<Value>? {
        guard let item = memory[key], let entry = item.value as? Entry<Value> else { return nil }
        clock &+= 1
        memory[key]?.access = clock
        return refreshed(entry)
    }

    private func remember<Value>(_ entry: Entry<Value>, key: String, bytes: Int) {
        // Serialized bytes underestimate decoded strings/arrays. Use a conservative
        // cost multiplier as well as a hard entry limit; disk remains the fallback.
        let cost = bytes * 4
        memoryBytes -= memory.removeValue(forKey: key)?.cost ?? 0
        guard maxMemoryEntries > 0, cost <= maxMemoryBytes else { return }
        clock &+= 1
        memory[key] = MemoryEntry(value: entry, cost: cost, access: clock)
        memoryBytes += cost
        while memory.count > maxMemoryEntries || memoryBytes > maxMemoryBytes {
            guard let oldest = memory.min(by: { $0.value.access < $1.value.access })?.key else { break }
            memoryBytes -= memory.removeValue(forKey: oldest)?.cost ?? 0
        }
    }

    func load<Value: Codable>(_ type: Value.Type, key: String) -> Entry<Value>? {
        lock.lock()
        defer { lock.unlock() }
        if let entry = memoryEntryLocked(type, key: key) { return entry }
        guard let data = try? Data(contentsOf: file(key)),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data),
              let result = refreshed(entry) else { return nil }
        remember(entry, key: key, bytes: data.count)
        return result
    }

    func save<Value: Codable>(_ value: Value, key: String, generation: UUID, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == revision else { return }
        let section = Self.section(for: key)
        let entry = Entry(value: value, savedAt: now, section: section, globalRevision: revisions.all,
                          sectionRevision: section.map { revisions.sections[$0] } ?? revisions.unknown)
        guard let data = try? JSONEncoder().encode(entry), data.count <= 4 * 1024 * 1024 else { return }
        remember(entry, key: key, bytes: data.count)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if revisionsDirty {
                try write(JSONEncoder().encode(revisions), to: directory.appendingPathComponent(".revisions"))
                revisionsDirty = false
            }
            try write(data, to: file(key))
            // Inventory disk once per instance, instead of sorting file metadata
            // again for every snapshot saved. The directory is still bounded.
            if diskEntries == nil {
                let files = try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey])
                diskEntries = Dictionary(uniqueKeysWithValues: files.filter { $0.pathExtension == "json" }.map {
                    ($0.lastPathComponent, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                })
            }
            diskEntries?[file(key).lastPathComponent] = now
            while (diskEntries?.count ?? 0) > maxEntries {
                guard let oldest = diskEntries?.min(by: { $0.value < $1.value })?.key else { break }
                let path = directory.appendingPathComponent(oldest)
                if FileManager.default.fileExists(atPath: path.path) {
                    try FileManager.default.removeItem(at: path)
                }
                diskEntries?[oldest] = nil
            }
        } catch { /* Caching must never prevent browsing. */ }
    }

    /// One small durable marker invalidates matching entries without rewriting
    /// any saved page. Their last values stay readable during the next refresh.
    func markStale(section: String? = nil) {
        lock.lock()
        revision = UUID()
        if let section { revisions.sections[section] = UUID() }
        else { revisions.all = UUID() }
        revisions.unknown = UUID()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(JSONEncoder().encode(revisions), to: directory.appendingPathComponent(".revisions"))
            revisionsDirty = false
        } catch {
            // If freshness cannot be persisted, discard disk copies instead.
            revisionsDirty = true
            try? FileManager.default.removeItem(at: directory)
            diskEntries = nil
        }
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        revision = UUID()
        revisions = Revisions(all: UUID())
        revisionsDirty = true
        memory.removeAll()
        memoryBytes = 0
        diskEntries = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func trimMemory() {
        lock.lock()
        defer { lock.unlock() }
        memory.removeAll()
        memoryBytes = 0
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private static func section(for key: String) -> String? {
        if let data = Data(base64Encoded: key),
           let fields = try? JSONDecoder().decode([String].self, from: data), fields.count >= 2 {
            return ["doubles", "vollis", "other"].contains(fields[1]) ? fields[1] : nil
        }
        return ["doubles", "vollis", "other"].first { key.contains("-\($0)-") }
    }

    private func file(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
