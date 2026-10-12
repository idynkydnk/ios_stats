import SwiftUI
import Foundation

// This harness intercepts the real client's request before it reaches the site.
// No recap is published and no subscriber email can be queued by these checks.
final class RecapRequestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    nonisolated override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let env = ProcessInfo.processInfo.environment
        let valid = request.url?.path == "/api/ai/summary"
            && request.httpMethod == "POST"
            && json["prompt_style"] as? String == "combined"
            && json["custom_prompt"] as? String == env["QA_PROMPT", default: ""]
            && json["image_mode"] as? String == env["QA_MODE", default: "none"]
            && json["image_details"] as? String == ""
            && json["game_type"] as? String == "doubles"
            && json["game_ids"] as? [String] == ["101", "102"]
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 400, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let result = valid ? "{\"success\":true,\"job_id\":42}" : "{\"error\":\"Recap request did not match the website contract\"}"
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    nonisolated override func stopLoading() {}
}

@main
struct LayoutCheckApp: App {
    @State private var queued = false
    init() { URLProtocol.registerClass(RecapRequestProtocol.self) }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack {
                    if queued { Text("Queued test recap #42").accessibilityIdentifier("recap-queued") }
                    SiteAIStyleView(gameType: "doubles", gameIds: ["101", "102"])
                }
            }
            .environment(\.aiSummaryQueued) { id in queued = id == 42 }
            .environment(\.siteAppearance, SiteAppearance())
            .preferredColorScheme(.dark)
        }
    }
}
