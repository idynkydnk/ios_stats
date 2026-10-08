import Foundation
import CryptoKit

/// Disposable, account-scoped snapshots. The server remains authoritative.
final class SiteBrowseCache: @unchecked Sendable {
    static let shared = SiteBrowseCache()
    struct Entry<Value: Codable>: Codable {
        var value: Value
        var savedAt: Date

        func isFresh(at now: Date = Date()) -> Bool {
            let age = now.timeIntervalSince(savedAt)
            return age >= 0 && age < 60
        }
    }

    private let directory: URL
    private let lock = NSLock()
    private var revision = UUID()
    private let maxEntries = 48

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StatsBrowse-v1", isDirectory: true)) {
        self.directory = directory
    }

    var generation: UUID {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    func load<Value: Codable>(_ type: Value.Type, key: String) -> Entry<Value>? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: file(key)),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data),
              Date().timeIntervalSince(entry.savedAt) < 30 * 24 * 60 * 60 else { return nil }
        return entry
    }

    func save<Value: Codable>(_ value: Value, key: String, generation: UUID, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        // A response started before a save, source change, or logout must not
        // repopulate invalidated data when it eventually finishes.
        guard generation == revision,
              let data = try? JSONEncoder().encode(Entry(value: value, savedAt: now)),
              data.count <= 4 * 1024 * 1024 else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file(key), options: .atomic)
            #endif
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey])
            let oldestFirst = files.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            for old in oldestFirst.prefix(max(0, files.count - maxEntries)) {
                try? FileManager.default.removeItem(at: old)
            }
        } catch { /* Caching must never prevent browsing. */ }
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        revision = UUID()
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
