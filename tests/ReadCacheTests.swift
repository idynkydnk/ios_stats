import Foundation

@main
struct ReadCacheTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = SiteBrowseCache(directory: directory)
        let cache = SiteReadCache<[String]>(cache: disk)
        var calls = 0
        var finish: CheckedContinuation<[String], Error>?
        let fetch: @MainActor () async throws -> [String] = {
            calls += 1
            return try await withCheckedThrowingContinuation { finish = $0 }
        }
        let first = Task { try await cache.load(key: "account-a", fetch: fetch) }
        while finish == nil { await Task.yield() }
        let second = Task { try await cache.load(key: "account-a", fetch: fetch) }
        // Let the second consumer reach the suspended shared request.
        try await Task.sleep(for: .milliseconds(30))
        first.cancel()
        precondition(calls == 1)
        finish!.resume(returning: ["2026"])
        do { _ = try await first.value; preconditionFailure("Canceled consumer applied data") }
        catch is CancellationError { }
        let result = try await second.value
        precondition(result == ["2026"])
        let reused = try await cache.load(key: "account-a", fetch: fetch)
        precondition(reused == result && calls == 1)
        let reopened = SiteReadCache<[String]>(cache: SiteBrowseCache(directory: directory))
        let restored = try await reopened.load(key: "account-a", fetch: fetch)
        precondition(restored == result && calls == 1)

        // An account/source change during a download rejects its late response.
        disk.markStale()
        finish = nil
        let late = Task { try await cache.load(key: "account-a", fetch: fetch) }
        while finish == nil { await Task.yield() }
        disk.invalidate()
        finish!.resume(returning: ["Old source"])
        do { _ = try await late.value; preconditionFailure("Accepted old revision") }
        catch is CancellationError { }
        precondition(disk.load([String].self, key: "account-a") == nil)
        let fresh = try await cache.load(key: "account-a") { ["New source"] }
        precondition(fresh == ["New source"])
        let separate = try await cache.load(key: "account-b") { ["Private B"] }
        precondition(separate == ["Private B"])
        enum Failure: Error { case expected }
        do { _ = try await cache.load(key: "failure") { throw Failure.expected }; preconditionFailure() }
        catch Failure.expected { }
        let retry = try await cache.load(key: "failure") { ["Retry"] }
        precondition(retry == ["Retry"])

        let gets = SiteGETRequests()
        var request = URLRequest(url: URL(string: "https://example.test/api/years?year=2026")!)
        request.httpMethod = "GET"
        request.setValue("Bearer account-a", forHTTPHeaderField: "Authorization")
        let key = SiteGETRequests.key(request)
        for header in ["Authorization", "X-Stats-Combined", "X-Stats-Owned", "X-Stats-Preview"] {
            var changed = request
            changed.setValue("different", forHTTPHeaderField: header)
            precondition(SiteGETRequests.key(changed) != key)
        }
        var filter = request
        filter.url = URL(string: "https://example.test/api/years?year=2025")!
        precondition(SiteGETRequests.key(filter) != key)
        precondition(SiteGETRequests.key(request, revision: "new") != key)
        var getCalls = 0
        var getFinish: CheckedContinuation<(Data, URLResponse), Error>?
        let get: @MainActor () async throws -> (Data, URLResponse) = {
            getCalls += 1
            return try await withCheckedThrowingContinuation { getFinish = $0 }
        }
        let a = Task { try await gets.load(key: key, fetch: get) }
        while getFinish == nil { await Task.yield() }
        let b = Task { try await gets.load(key: key, fetch: get) }
        try await Task.sleep(for: .milliseconds(30))
        a.cancel()
        precondition(getCalls == 1)
        let response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 1, textEncodingName: nil)
        getFinish!.resume(returning: (Data([1]), response))
        do { _ = try await a.value; preconditionFailure() } catch is CancellationError { }
        let data = try await b.value.0
        precondition(data == Data([1]))
        // Transport only shares in-flight work; subsequent reads are fresh.
        let later = try await gets.load(key: key) { getCalls += 1; return (Data([2]), response) }
        precondition(later.0 == Data([2]) && getCalls == 2)
        print("Read cache: shared downloads, cancellation, persistence, isolation, revision changes and retries passed.")
    }
}
