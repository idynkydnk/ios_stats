import Foundation
import Combine

final class PythonAnywhereClient {
    static let shared = PythonAnywhereClient()

    let baseURL = URL(string: "https://idynkydnk.pythonanywhere.com")!
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    private var token: String? { SiteAuthManager.shared.token }

    func login(username: String, password: String) async throws -> MePayload {
        struct Body: Encodable { var username: String; var password: String }
        struct LoginResp: Decodable { var token: String; var username: String }
        let resp: LoginResp = try await post("/api/auth/login", body: Body(username: username, password: password), authed: false)
        await MainActor.run {
            SiteAuthManager.shared.storeToken(resp.token, username: resp.username)
        }
        if let me: MePayload = try? await get("/api/me") {
            return me
        }
        return MePayload(username: resp.username, isAdmin: username.lowercased() == "kyle", loggedIn: true)
    }

    func logout() async throws {
        struct Empty: Encodable {}
        struct Ok: Decodable { var ok: Bool? }
        _ = try? await post("/api/auth/logout", body: Empty(), authed: true) as Ok
    }

    func me() async throws -> MePayload { try await get("/api/me") }

    func years() async throws -> YearsPayload { try await get("/api/years") }

    func doublesStats(year: String) async throws -> DoublesStatsPayload {
        try await get("/api/doubles/stats", query: ["year": year])
    }

    func doublesGames(year: String? = nil, since: String? = nil) async throws -> GamesListPayload<DoublesGame> {
        var q: [String: String] = [:]
        if let year { q["year"] = year }
        if let since { q["since"] = since }
        return try await get("/api/doubles/games", query: q)
    }

    func createDoubles(_ fields: [String: Any]) async throws -> DoublesGame {
        try await postJSON("/api/doubles/games", json: fields)
    }

    func updateDoubles(id: Int, fields: [String: Any]) async throws -> DoublesGame {
        try await putJSON("/api/doubles/games/\(id)", json: fields)
    }

    func deleteDoubles(id: Int) async throws {
        try await delete("/api/doubles/games/\(id)")
    }

    func doublesPlayer(name: String, year: String) async throws -> DoublesPlayerPayload {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return try await get("/api/doubles/players/\(encoded)", query: ["year": year])
    }

    func network(year: String) async throws -> NetworkPayload {
        try await get("/api/network", query: ["year": year])
    }

    func vollisStats(year: String) async throws -> VollisStatsPayload {
        try await get("/api/vollis/stats", query: ["year": year])
    }

    func vollisGames(year: String? = nil) async throws -> GamesListPayload<VollisGame> {
        var q: [String: String] = [:]
        if let year { q["year"] = year }
        return try await get("/api/vollis/games", query: q)
    }

    func createVollis(_ fields: [String: Any]) async throws {
        struct Msg: Decodable { var message: String?; var id: Int? }
        let _: Msg = try await postJSON("/api/vollis/games", json: fields)
    }

    func updateVollis(id: Int, fields: [String: Any]) async throws {
        struct Msg: Decodable { var winner: String? }
        let _: VollisGame = try await putJSON("/api/vollis/games/\(id)", json: fields)
    }

    func deleteVollis(id: Int) async throws { try await delete("/api/vollis/games/\(id)") }

    func vollisPlayer(name: String, year: String) async throws -> DoublesPlayerPayload {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return try await get("/api/vollis/players/\(encoded)", query: ["year": year])
    }

    func otherPlayer(name: String, year: String) async throws -> DoublesPlayerPayload {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return try await get("/api/other/players/\(encoded)", query: ["year": year])
    }

    func otherStats(year: String) async throws -> OtherStatsPayload {
        try await get("/api/other/stats", query: ["year": year])
    }

    func otherGames(year: String? = nil, gameName: String? = nil) async throws -> GamesListPayload<OtherGame> {
        var q: [String: String] = [:]
        if let year { q["year"] = year }
        if let gameName { q["game_name"] = gameName }
        return try await get("/api/other/games", query: q)
    }

    func createOther(_ fields: [String: Any]) async throws {
        struct Msg: Decodable { var message: String?; var id: Int? }
        let _: Msg = try await postJSON("/api/other/games", json: fields)
    }

    func updateOther(id: Int, fields: [String: Any]) async throws {
        struct Msg: Decodable { var message: String? }
        let _: Msg = try await putJSON("/api/other/games/\(id)", json: fields)
    }

    func deleteOther(id: Int) async throws { try await delete("/api/other/games/\(id)") }

    func volleyballStats(year: String) async throws -> OtherStatsPayload {
        struct VB: Codable {
            var year: String
            var allYears: [String]
            var gameCards: [SiteGameCard]
        }
        let vb: VB = try await get("/api/volleyball/stats", query: ["year": year])
        return OtherStatsPayload(
            year: vb.year, displayYear: vb.year, showingPreviousYear: false,
            minimumGames: nil, allYears: vb.allYears, stats: [], rareStats: [],
            gameCards: vb.gameCards, todayStatsByGame: [], todayGames: []
        )
    }

    func otherGameInfo(name: String) async throws -> [String: Any] {
        try await getJSON("/api/other_game_info/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")
    }

    func players() async throws -> [SitePlayer] {
        struct Wrap: Codable { var players: [SitePlayer] }
        let w: Wrap = try await get("/api/players")
        return w.players
    }

    func addPlayer(fullName: String, email: String? = nil) async throws {
        struct Resp: Decodable { var success: Bool?; var error: String? }
        var payload: [String: Any] = ["full_name": fullName]
        if let email, !email.isEmpty { payload["email"] = email }
        let r: Resp = try await postJSON("/api/add_player", json: payload)
        if r.success == false { throw SiteAPIError.message(r.error ?? "Could not add player") }
    }

    func updatePlayerInfo(_ fields: [String: Any]) async throws {
        struct Resp: Decodable { var success: Bool?; var error: String? }
        let r: Resp = try await postJSON("/api/update_player_info", json: fields)
        if r.success == false { throw SiteAPIError.message(r.error ?? "Update failed") }
    }

    func renamePlayer(oldName: String, newName: String) async throws {
        struct Resp: Decodable { var success: Bool?; var error: String? }
        let r: Resp = try await postJSON("/api/rename_player", json: ["old_name": oldName, "new_name": newName])
        if r.success == false { throw SiteAPIError.message(r.error ?? "Rename failed") }
    }

    func uploadPlayerPhoto(name: String, imageData: Data, filename: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        try await upload("/api/player_photo/\(encoded)/", imageData: imageData, filename: filename)
    }

    func searchPlayers(q: String) async throws -> [[String: Any]] {
        let raw = try await getRaw("/api/search_all_players", query: ["q": q])
        let obj = try JSONSerialization.jsonObject(with: raw)
        if let rows = obj as? [[String: Any]] { return rows }
        if let dict = obj as? [String: Any], let rows = dict["players"] as? [[String: Any]] { return rows }
        return []
    }

    func otherGameTypes() async throws -> (names: [String], types: [String]) {
        struct Wrap: Codable {
            var gameNames: [String]?
            var gameTypes: [String]?
        }
        let w: Wrap = try await get("/api/other/game-types")
        return (w.gameNames ?? [], w.gameTypes ?? [])
    }

    func doublesPlayers() async throws -> [String] {
        try await nameList("/api/doubles_players")
    }

    func vollisPlayers() async throws -> [String] {
        try await nameList("/api/vollis_players")
    }

    func otherGamePlayers(gameName: String) async throws -> [String] {
        let encoded = gameName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? gameName
        return try await nameList("/api/other_game_players/\(encoded)")
    }

    func otherGameCommonScores(gameName: String) async throws -> (winners: [Int], losers: [Int], winnerIndiv: [Int], loserIndiv: [Int]) {
        let encoded = gameName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? gameName
        let json = try await getJSON("/api/other_game_common_scores/\(encoded)")
        let w = (json["winner_scores"] as? [Any] ?? []).compactMap { Self.jsonInt($0) }
        let l = (json["loser_scores"] as? [Any] ?? []).compactMap { Self.jsonInt($0) }
        let wi = (json["winner_individual_scores"] as? [Any] ?? []).compactMap { Self.jsonInt($0) }
        let li = (json["loser_individual_scores"] as? [Any] ?? []).compactMap { Self.jsonInt($0) }
        return (w, l, wi, li)
    }

    func todaysDoublesDashboard() async throws -> TodaysDoublesDashboard {
        let json = try await getJSON("/api/todays_doubles_dashboard")
        let year = json["year"] as? String ?? ""
        var stats: [RankingRow] = []
        if let rows = json["stats"] as? [Any] {
            for row in rows {
                let arr = row as? [Any] ?? []
                let name = arr.first as? String ?? ""
                let wins = arr.count > 1 ? (Self.jsonInt(arr[1]) ?? 0) : 0
                let losses = arr.count > 2 ? (Self.jsonInt(arr[2]) ?? 0) : 0
                let pct = arr.count > 3 ? (Self.jsonDouble(arr[3]) ?? 0) : 0
                let pm = arr.count > 4 ? Self.jsonInt(arr[4]) : nil
                if !name.isEmpty {
                    stats.append(RankingRow(name: name, wins: wins, losses: losses, winPct: pct, plusMinus: pm))
                }
            }
        }
        var games: [DoublesGame] = []
        if let rows = json["games"] as? [Any] {
            for row in rows {
                guard let g = row as? [String: Any] else { continue }
                games.append(DoublesGame(
                    id: Self.jsonInt(g["id"]) ?? 0,
                    gameDate: g["when"] as? String ?? g["game_date"] as? String,
                    winner1: g["winner1"] as? String,
                    winner2: g["winner2"] as? String,
                    winnerScore: Self.jsonInt(g["winner_score"]),
                    loser1: g["loser1"] as? String,
                    loser2: g["loser2"] as? String,
                    loserScore: Self.jsonInt(g["loser_score"]),
                    updatedAt: nil,
                    comments: g["comment"] as? String ?? g["comments"] as? String,
                    enteredTimezone: nil,
                    updatedBy: nil
                ))
            }
        }
        return TodaysDoublesDashboard(year: year, stats: stats, games: games)
    }

    private func nameList(_ path: String) async throws -> [String] {
        let raw = try await getRaw(path)
        if let names = try JSONSerialization.jsonObject(with: raw) as? [String] { return names }
        if let objs = try JSONSerialization.jsonObject(with: raw) as? [[String: Any]] {
            return objs.compactMap { $0["name"] as? String ?? $0["full_name"] as? String }
        }
        return []
    }

    static func jsonIntPublic(_ v: Any?) -> Int? { jsonInt(v) }

    private static func jsonInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    private static func jsonDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    func tournaments() async throws -> [Tournament] {
        struct Wrap: Codable { var tournaments: [Tournament] }
        let w: Wrap = try await get("/api/tournaments")
        return w.tournaments
    }

    func addTournament(_ fields: [String: String]) async throws {
        struct T: Codable { var id: Int? }
        let _: T = try await postJSON("/api/tournaments", json: fields)
    }

    func parseVoice(transcript: String) async throws -> [String: Any] {
        try await postJSONDict("/api/parse_voice_doubles", json: ["transcript": transcript])
    }

    func generateAISummary(gameType: String, gameIds: [String], promptStyle: String = "default", customPrompt: String = "") async throws -> Int {
        struct Resp: Decodable { var success: Bool?; var jobId: Int?; var error: String? }
        let r: Resp = try await postJSON("/api/ai/summary", json: [
            "game_type": gameType,
            "game_ids": gameIds,
            "prompt_style": promptStyle,
            "custom_prompt": customPrompt,
        ])
        if let id = r.jobId { return id }
        throw SiteAPIError.message(r.error ?? "Could not queue recap")
    }

    func recaps() async throws -> [RecapItem] {
        struct Wrap: Codable { var recaps: [RecapItem] }
        let w: Wrap = try await get("/api/ai/recaps")
        return w.recaps
    }

    func createFlyer(_ fields: [String: Any]) async throws -> Int {
        struct Resp: Decodable { var success: Bool?; var jobId: Int?; var error: String? }
        let r: Resp = try await postJSON("/api/flyers", json: fields)
        if let id = r.jobId { return id }
        throw SiteAPIError.message(r.error ?? "Could not queue flyer")
    }

    func aiJob(id: Int) async throws -> [String: Any] {
        try await getJSON("/api/ai/jobs/\(id)")
    }

    func searchAIGames(q: String, gameType: String) async throws -> [[String: Any]] {
        let json = try await getJSON("/api/ai_summary_game_search/", query: ["q": q, "game_type": gameType])
        return json["games"] as? [[String: Any]] ?? []
    }

    func adminOverview() async throws -> [String: Any] { try await getJSON("/api/admin/overview") }
    func adminActivity(page: Int = 1) async throws -> [String: Any] {
        try await getJSON("/api/admin/activity", query: ["page": String(page)])
    }
    func adminUndo(id: Int) async throws {
        struct Ok: Decodable { var ok: Bool?; var error: String? }
        let r: Ok = try await postJSON("/api/admin/undo/\(id)", json: [String: String]())
        if r.ok == false { throw SiteAPIError.message(r.error ?? "Undo failed") }
    }
    func adminAddUser(username: String, password: String, isAdmin: Bool) async throws {
        struct Ok: Decodable { var ok: Bool?; var error: String? }
        let r: Ok = try await postJSON("/api/admin/users", json: ["username": username, "password": password, "is_admin": isAdmin])
        if let err = r.error, r.ok != true { throw SiteAPIError.message(err) }
    }
    func adminResetPassword(username: String, password: String) async throws {
        struct Ok: Decodable { var ok: Bool? }
        let _: Ok = try await postJSON("/api/admin/users/reset_password", json: ["username": username, "password": password])
    }
    func adminToggleActive(username: String, active: Bool) async throws {
        struct Ok: Decodable { var ok: Bool? }
        let _: Ok = try await postJSON("/api/admin/users/toggle_active", json: ["username": username, "active": active])
    }
    func adminBackup() async throws {
        struct Ok: Decodable { var ok: Bool?; var filename: String? }
        let _: Ok = try await postJSON("/api/admin/backup", json: [String: String]())
    }
    func adminClearCache() async throws {
        struct Ok: Decodable { var ok: Bool? }
        let _: Ok = try await postJSON("/api/admin/clear_cache", json: [String: String]())
    }
    func adminTestEmail() async throws {
        struct Ok: Decodable { var ok: Bool?; var error: String? }
        let r: Ok = try await postJSON("/api/admin/test_email", json: [String: String]())
        if let err = r.error { throw SiteAPIError.message(err) }
    }

    // MARK: - HTTP

    private func url(_ path: String, query: [String: String] = [:]) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path), resolvingAgainstBaseURL: false)!
        // appendingPathComponent strips empty; keep original path
        comps = URLComponents(string: baseURL.absoluteString + (path.hasPrefix("/") ? path : "/" + path))!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url!
    }

    private func request(_ path: String, method: String, query: [String: String] = [:], authed: Bool = true) -> URLRequest {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authed, let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let req = request(path, method: "GET", query: query, authed: token != nil)
        return try await decode(req)
    }

    private func getRaw(_ path: String, query: [String: String] = [:]) async throws -> Data {
        let req = request(path, method: "GET", query: query, authed: token != nil)
        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(data, resp)
        return data
    }

    private func getJSON(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        let data = try await getRaw(path, query: query)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, authed: Bool) async throws -> T {
        var req = request(path, method: "POST", authed: authed)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        return try await decode(req)
    }

    private func postJSON<T: Decodable>(_ path: String, json: Any) async throws -> T {
        var req = request(path, method: "POST", authed: true)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await decode(req)
    }

    private func postJSONDict(_ path: String, json: Any) async throws -> [String: Any] {
        var req = request(path, method: "POST", authed: true)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(data, resp)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func putJSON<T: Decodable>(_ path: String, json: Any) async throws -> T {
        var req = request(path, method: "PUT", authed: true)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await decode(req)
    }

    private func delete(_ path: String) async throws {
        let req = request(path, method: "DELETE", authed: true)
        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(data, resp)
    }

    private func upload(_ path: String, imageData: Data, filename: String) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = request(path, method: "POST", authed: true)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(data, resp)
    }

    private func decode<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(data, resp)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SiteAPIError.message("Could not read server response. \(error.localizedDescription)")
        }
    }

    private func throwIfNeeded(_ data: Data, _ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw SiteAPIError.unauthorized }
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 404 {
            throw SiteAPIError.message("The live site doesn’t have this API yet. Push the website repo to PythonAnywhere, then try again.")
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let msg = (obj["error"] as? String) ?? (obj["message"] as? String) ?? ""
            throw SiteAPIError.http(http.statusCode, msg)
        }
        throw SiteAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }
}

final class SiteOfflineQueue: ObservableObject {
    static let shared = SiteOfflineQueue()
    private let key = "com.kt.stats.pa.offline_queue"
    @Published var items: [OfflineMutation] = []

    private init() { load() }

    func enqueue(method: String, path: String, body: [String: Any]?) {
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let item = OfflineMutation(id: UUID().uuidString, method: method, path: path, body: data)
        items.append(item)
        save()
    }

    func flush() async {
        let pending = items
        for item in pending {
            do {
                var json: Any = [String: Any]()
                if let body = item.body {
                    json = (try? JSONSerialization.jsonObject(with: body)) ?? [:]
                }
                switch item.method {
                case "POST":
                    struct Msg: Decodable { var message: String? }
                    let _: Msg = try await PythonAnywhereClient.shared.postJSONPublic(item.path, json: json)
                case "PUT":
                    struct Msg: Decodable { var message: String? }
                    let _: Msg = try await PythonAnywhereClient.shared.putJSONPublic(item.path, json: json)
                case "DELETE":
                    try await PythonAnywhereClient.shared.deletePublic(item.path)
                default:
                    break
                }
                await MainActor.run {
                    items.removeAll { $0.id == item.id }
                    save()
                }
            } catch {
                break
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([OfflineMutation].self, from: data) else { return }
        items = decoded
    }
}

extension PythonAnywhereClient {
    func postJSONPublic<T: Decodable>(_ path: String, json: Any) async throws -> T {
        try await postJSON(path, json: json)
    }
    func putJSONPublic<T: Decodable>(_ path: String, json: Any) async throws -> T {
        try await putJSON(path, json: json)
    }
    func deletePublic(_ path: String) async throws {
        try await delete(path)
    }
}
