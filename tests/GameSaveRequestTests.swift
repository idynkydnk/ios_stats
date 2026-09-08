import Foundation

@main
struct GameSaveRequestTests {
    static func main() async throws {
        let url = URL(string: "https://example.invalid/api/doubles/games")!
        var post = URLRequest(url: url)
        post.httpMethod = "POST"
        let get = URLRequest(url: url)
        let fields: [String: Any] = [
            "game_date": "2026-09-07 10:12:34", "winner1": "A", "winner2": "B",
            "loser1": "C", "loser2": "D", "winner_score": 21, "loser_score": 17,
            "location": "Beach", "comments": "", "entered_timezone": "America/Los_Angeles"
        ]
        var saved = fields
        saved["id"] = 42
        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        }
        let savedData = try JSONSerialization.data(withJSONObject: ["games": [saved]])
        // Successful writes require no particular response shape, even an empty body.
        for body in [Data(), Data("{\"message\":\"Game created\"}".utf8), Data("unreadable".utf8)] {
            var calls = 0
            try await SiteGameSaveRequest.send(post, confirmationRequest: get, fields: fields) { _ in
                calls += 1
                return (body, response(201))
            }
            precondition(calls == 1)
        }
        // A server error after commit and a dropped response both recover via GET.
        for timeout in [false, true] {
            var methods: [String] = []
            try await SiteGameSaveRequest.send(post, confirmationRequest: get, fields: fields, retryDelay: .zero) { request in
                methods.append(request.httpMethod!)
                if request.httpMethod == "POST" {
                    if timeout { throw URLError(.timedOut) }
                    return (Data(), response(500))
                }
                return (savedData, response(200))
            }
            precondition(methods == ["POST", "GET"])
        }
        // Allow a committed game to become visible on the second read.
        var reads = 0
        try await SiteGameSaveRequest.send(post, confirmationRequest: get, fields: fields, retryDelay: .zero) { request in
            if request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
            reads += 1
            return (reads == 1 ? Data("{\"games\":[]}".utf8) : savedData, response(200))
        }
        precondition(reads == 2)
        // Repeated scores/names from an earlier game must not count as confirmation.
        var oldGame = saved
        oldGame["game_date"] = "2026-09-07 10:11:34"
        precondition(!SiteGameSaveRequest.matches(oldGame, fields: fields))
        for key in ["winner1", "loser2", "winner_score", "location", "id"] {
            var mismatch = saved
            mismatch.removeValue(forKey: key)
            precondition(!SiteGameSaveRequest.matches(mismatch, fields: fields))
        }
        let vollis: [String: Any] = ["game_date": "2026-09-07 10:12:34", "winner": "A", "loser": "B", "winner_score": 11, "loser_score": 8]
        var savedVollis = vollis
        savedVollis["id"] = 43
        precondition(SiteGameSaveRequest.matches(savedVollis, fields: vollis))
        // Validation and authorization failures must remain failures, without a lookup.
        for status in [400, 401, 403, 422] {
            var calls = 0
            do {
                try await SiteGameSaveRequest.send(post, confirmationRequest: get, fields: fields) { _ in
                    calls += 1
                    return (Data("{\"error\":\"Rejected\"}".utf8), response(status))
                }
                fatalError("Accepted rejected write")
            } catch SiteGameSaveRequest.SaveError.rejected(let code, _) {
                precondition(code == status && calls == 1)
            }
        }
        // Unconfirmed saves retain an explicit unknown outcome; never retry the write.
        var methods: [String] = []
        do {
            try await SiteGameSaveRequest.send(post, confirmationRequest: get, fields: fields, retryDelay: .zero) { request in
                methods.append(request.httpMethod!)
                if request.httpMethod == "POST" { throw URLError(.timedOut) }
                return (Data("{\"games\":[]}".utf8), response(200))
            }
            fatalError("Accepted unconfirmed write")
        } catch SiteGameSaveRequest.SaveError.unconfirmed {
            precondition(methods == ["POST", "GET", "GET"])
        }
        print("Game save regression checks passed")
    }
}
