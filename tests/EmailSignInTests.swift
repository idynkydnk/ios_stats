import Foundation

final class EmailStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct EmailSignInTests {
    static func body(_ request: URLRequest) throws -> [String: String] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    @MainActor
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmailStubProtocol.self]
        let flow = SiteEmailSignIn(baseURL: URL(string: "https://stats.example")!, session: URLSession(configuration: configuration))
        EmailStubProtocol.handler = { request in
            precondition(request.httpMethod == "GET")
            precondition(request.url?.path == "/api/auth/email")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer existing-token")
            return (200, #"{"step":"email","csrf":"start-csrf","enrolling":true}"#)
        }
        let initial = try await flow.request(bearer: "existing-token")
        precondition(initial == nil && flow.state?.enrolling == true)

        EmailStubProtocol.handler = { request in
            let fields = try body(request)
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            precondition(fields == ["action": "send", "email": "player@example.com", "csrf": "start-csrf"])
            return (200, #"{"step":"code","csrf":"code-csrf","email":"player@example.com"}"#)
        }
        let sent = try await flow.request(["action": "send", "email": "player@example.com"])
        precondition(sent == nil && flow.state?.step == .code)

        EmailStubProtocol.handler = { request in
            let fields = try body(request)
            precondition(fields["csrf"] == "code-csrf")
            precondition(fields["code"] == "0007")
            return (429, #"{"step":"code","csrf":"retry-csrf","error":"Please wait before trying again."}"#)
        }
        do {
            _ = try await flow.request(["action": "verify", "code": "0007"])
            preconditionFailure("Server errors must not be accepted as sign-in")
        } catch {
            precondition(error.localizedDescription == "Please wait before trying again.")
            precondition(flow.state?.csrf == "retry-csrf")
            precondition(flow.state?.step == .code)
        }
        EmailStubProtocol.handler = { request in
            let fields = try body(request)
            precondition(fields["csrf"] == "retry-csrf")
            return (200, #"{"step":"signup","csrf":"name-csrf"}"#)
        }
        _ = try await flow.request(["action": "verify", "code": "0007"])
        precondition(flow.state?.step == .signup)
        EmailStubProtocol.handler = { request in
            let fields = try body(request)
            precondition(fields["first_name"] == "alex" && fields["last_name"] == "SMITH")
            precondition(fields["csrf"] == "name-csrf")
            return (200, #"{"step":"complete","token":"verified-token"}"#)
        }
        let token = try await flow.request(["action": "signup", "first_name": "alex", "last_name": "SMITH"])
        precondition(token == "verified-token")
        precondition(flow.state?.step == .complete)

        // A missing token and an HTML outage must remain errors, not successful sign-ins.
        EmailStubProtocol.handler = { _ in (200, #"{"step":"complete"}"#) }
        do { _ = try await flow.request(); preconditionFailure("Missing token accepted") }
        catch { precondition(error.localizedDescription.contains("did not finish")) }
        EmailStubProtocol.handler = { _ in (503, "<html>Unavailable</html>") }
        do { _ = try await flow.request(); preconditionFailure("HTML accepted") }
        catch { precondition(error.localizedDescription.contains("temporarily unavailable")) }
        print("Email sign-in transport checks passed")
    }
}
