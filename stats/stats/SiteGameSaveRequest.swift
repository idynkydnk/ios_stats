import Foundation

/// A committed write must not become a failure just because its response body
/// changed. If confirmation was lost, only an exact saved record confirms it.
enum SiteGameSaveRequest {
    enum SaveError: LocalizedError {
        case rejected(Int, String)
        case unconfirmed

        var errorDescription: String? {
            switch self {
            case .rejected(401, _): return "Please log in."
            case .rejected(let status, let message):
                return message.isEmpty ? "Could not save game (HTTP \(status))." : message
            case .unconfirmed:
                return "Could not confirm whether the game was saved. Your entries are kept. Check Today's Games before trying again."
            }
        }
    }

    static func send(
        _ request: URLRequest,
        confirmationRequest: URLRequest?,
        fields: [String: Any],
        retryDelay: Duration = .milliseconds(750),
        transport: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws {
        do {
            let (data, response) = try await transport(request)
            guard let http = response as? HTTPURLResponse else { throw SaveError.unconfirmed }
            if (200..<300).contains(http.statusCode) { return }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw SaveError.rejected(http.statusCode, body?["error"] as? String ?? body?["message"] as? String ?? "")
        } catch {
            if case SaveError.rejected(let status, _) = error, (400..<500).contains(status) {
                throw error
            }
            // Never repeat the POST: the server may already have committed it.
            if let confirmationRequest {
                for attempt in 0..<2 {
                    if attempt > 0 { try await Task.sleep(for: retryDelay) }
                    if let (data, response) = try? await transport(confirmationRequest),
                       let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                       let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let games = body["games"] as? [[String: Any]],
                       games.contains(where: { matches($0, fields: fields) }) {
                        return
                    }
                }
            }
            throw SaveError.unconfirmed
        }
    }

    static func matches(_ game: [String: Any], fields: [String: Any]) -> Bool {
        guard game["id"] is NSNumber,
              let date = fields["game_date"] as? String, !date.isEmpty,
              game["game_date"] as? String == date else { return false }
        // These APIs preserve the submitted timestamp to the second. Matching
        // names/scores alone could mistake a previous rematch for this save.
        let names = fields["winner1"] != nil
            ? ["winner1", "winner2", "loser1", "loser2"] : ["winner", "loser"]
        for key in names {
            guard let expected = fields[key] as? String, !expected.isEmpty,
                  game[key] as? String == expected else { return false }
        }
        for key in ["winner_score", "loser_score"] {
            guard let expected = fields[key] as? NSNumber,
                  let actual = game[key] as? NSNumber, actual == expected else { return false }
        }
        for key in ["comments", "location", "entered_timezone"] {
            if let expected = fields[key] as? String,
               (game[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                != expected.trimmingCharacters(in: .whitespacesAndNewlines) { return false }
        }
        return true
    }
}
