import Foundation
import Supabase

/// Backend using Supabase (PostgreSQL + Auth).
/// Configure via Supabase-Info.plist: SUPABASE_URL, SUPABASE_ANON_KEY.
final class SupabaseManager: @unchecked Sendable {
    static let shared = SupabaseManager()

    private var client: SupabaseClient?
    private let configQueue = DispatchQueue(label: "com.stats.supabase.config")

    /// In-memory cache of players per database (for instant autocomplete).
    private var playersCache: [String: [PlayerInfo]] = [:]
    private let playersCacheLock = NSLock()

    /// Pagination cursor for "Load more" games (last game id per dbId).
    private var gamesPageCursors: [String: String] = [:]
    private let gamesPageCursorsLock = NSLock()

    private init() {
        loadConfig()
    }

    private func loadConfig() {
        guard let url = Bundle.main.url(forResource: "Supabase-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let base = dict["SUPABASE_URL"] as? String,
              let key = dict["SUPABASE_ANON_KEY"] as? String,
              let supabaseURL = URL(string: base), !key.isEmpty else {
            return
        }
        configQueue.sync {
            client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: key)
        }
    }

    /// Use this client for DB operations. Returns nil if not configured.
    private var supabase: SupabaseClient? {
        configQueue.sync { client }
    }

    private func run<T>(_ work: @escaping () async throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        Task {
            do {
                let value = try await work()
                DispatchQueue.main.async { completion(.success(value)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Same public API as FirebaseManager

    func cachedPlayers(dbId: String, editorDbId: String? = nil) -> [PlayerInfo]? {
        playersCacheLock.withLock {
            playersCache[playersCacheKey(dbId: dbId, editorDbId: editorDbId)]
        }
    }

    func prefetchPlayers(dbId: String, editorDbId: String? = nil) {
        fetchAllPlayers(dbId: dbId, editorDbId: editorDbId) { _ in }
    }

    private func playersCacheKey(dbId: String, editorDbId: String?) -> String {
        "\(dbId)_\(editorDbId ?? "")"
    }

    func fetchGames(dbId: String, limit: Int? = nil, completion: @escaping (Result<[LegacyGame], Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        if limit == nil {
            _ = gamesPageCursorsLock.withLock {
                gamesPageCursors.removeValue(forKey: dbId)
            }
        }
        run {
            let query = supabase.from("games")
                .select()
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .order("game_date", ascending: false)
            let rows: [GameRow]
            if let limit = limit, limit > 0 {
                rows = try await query.limit(limit).execute().value
            } else {
                rows = try await query.execute().value
            }
            let games = rows.map { $0.toLegacyGame() }
            if let limit = limit, limit > 0, games.count == limit {
                self.gamesPageCursorsLock.withLock {
                    self.gamesPageCursors[dbId] = String(limit)
                }
            } else {
                _ = self.gamesPageCursorsLock.withLock {
                    self.gamesPageCursors.removeValue(forKey: dbId)
                }
            }
            return games
        } completion: { completion($0) }
    }

    func loadMoreGames(dbId: String, limit: Int = 25, completion: @escaping (Result<[LegacyGame], Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.success([])) }
            return
        }
        let offset: Int = {
            gamesPageCursorsLock.withLock {
                Int(gamesPageCursors[dbId] ?? "0") ?? 0
            }
        }()
        run {
            let rows: [GameRow] = try await supabase.from("games")
                .select()
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .order("game_date", ascending: false)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
            let games = rows.map { $0.toLegacyGame() }
            let nextOffset = offset + rows.count
            self.gamesPageCursorsLock.withLock {
                if rows.count == limit {
                    self.gamesPageCursors[dbId] = String(nextOffset)
                } else {
                    self.gamesPageCursors.removeValue(forKey: dbId)
                }
            }
            return games
        } completion: { completion($0) }
    }

    func hasMoreGames(dbId: String) -> Bool {
        gamesPageCursorsLock.withLock {
            gamesPageCursors[dbId] != nil
        }
    }

    func insertGame(dbId: String, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, comment: String = "", editorDbId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        insertGame(dbId: dbId, date: Date(), winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore, comment: comment, editorDbId: editorDbId) { result in
            completion(result.map { _ in () })
        }
    }

    func insertGame(dbId: String, date: Date, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, comment: String = "", editorDbId: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            try await self.ensureDatabaseExists(dbId: dbId, supabase: supabase)
            try await self.ensurePlayersExist(dbId: dbId, names: [winner1, winner2, loser1, loser2], supabase: supabase)
            let editorUUID = editorDbId.flatMap { UUID(uuidString: $0) }
            let row = GameRow(
                id: UUID(),
                db_id: dbUUID,
                game_date: date,
                winner1: winner1,
                winner2: winner2,
                winner_score: winnerScore,
                loser1: loser1,
                loser2: loser2,
                loser_score: loserScore,
                comments: comment,
                updated_at: nil,
                entered_timezone: TimeZone.current.identifier,
                updated_by: AuthManager.shared.currentUser?.displayName ?? AuthManager.shared.userEmail ?? "",
                editor_db_id: editorUUID
            )
            try await supabase.from("games").insert(row).execute()
            try await self.updateStatsAfterGame(dbId: dbId, gameDate: date, winner1: winner1, winner2: winner2, loser1: loser1, loser2: loser2, supabase: supabase)
            let summary = "\(winner1), \(winner2) beat \(loser1), \(loser2) \(winnerScore)-\(loserScore)"
            try await self.logActivity(dbId: dbId, action: "add_game", editorDbId: editorDbId, gameId: row.id.uuidString, summary: summary, supabase: supabase)
            return row.id.uuidString
        } completion: { completion($0) }
    }

    func updateGame(dbId: String, documentId: String, winner1: String, winner2: String, winnerScore: Int, loser1: String, loser2: String, loserScore: Int, comment: String = "", editorDbId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let gameUUID = UUID(uuidString: documentId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            try await supabase.from("games")
                .update(GameUpdate(winner1: winner1, winner2: winner2, winner_score: winnerScore, loser1: loser1, loser2: loser2, loser_score: loserScore, comments: comment, updated_at: Date()))
                .eq("id", value: gameUUID.uuidString)
                .execute()
            try await self.setStatsRecomputeRequired(dbId: dbId, supabase: supabase)
            let summary = "\(winner1), \(winner2) vs \(loser1), \(loser2) \(winnerScore)-\(loserScore)"
            try await self.logActivity(dbId: dbId, action: "update_game", editorDbId: editorDbId, gameId: documentId, summary: summary, supabase: supabase)
            return ()
        } completion: { completion($0) }
    }

    func deleteGame(dbId: String, documentId: String, editorDbId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let gameUUID = UUID(uuidString: documentId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            try await supabase.from("games").delete().eq("id", value: gameUUID.uuidString).execute()
            try await self.setStatsRecomputeRequired(dbId: dbId, supabase: supabase)
            try await self.logActivity(dbId: dbId, action: "delete_game", editorDbId: editorDbId, gameId: documentId, summary: nil, supabase: supabase)
            return ()
        } completion: { completion($0) }
    }

    func fetchPlayerStats(dbId: String, year: String, completion: @escaping (Result<(stats: [(name: String, wins: Int, losses: Int, trueSkill: Double)], years: [String]), Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            let row: StatsAggregateRow? = try await supabase.from("stats_aggregate")
                .select()
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .single()
                .execute()
                .value
            guard let r = row, !(r.recompute_required ?? true) else {
                let (allTime, byYear) = try await self.recomputeAndWriteStats(dbId: dbId, supabase: supabase)
                let out = year == "All" ? allTime : (byYear[year] ?? allTime)
                let years = ["All"] + byYear.keys.sorted(by: >)
                return (out, years)
            }
            let allTimeDict = r.allTimeDict ?? [:]
            let byYearDict = r.byYearDict ?? [:]
            let allTime = self.parseStatsPlayers(allTimeDict)
            let out = year == "All" ? allTime : (self.parseStatsByYear(byYearDict, year: year) ?? allTime)
            let stored = r.years ?? []
            let rest = stored.filter { $0 != "All" }
            let years = ["All"] + rest.sorted(by: >)
            return (out, years)
        } completion: { completion($0) }
    }

    func setStatsRecomputeRequired(dbId: String, completion: (() -> Void)? = nil) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion?() }
            return
        }
        Task {
            struct RecomputeFlag: Codable {
                let db_id: UUID
                let recompute_required: Bool
            }
            _ = try? await supabase.from("stats_aggregate").upsert(RecomputeFlag(db_id: dbUUID, recompute_required: true)).eq("db_id", value: dbUUID.uuidString).execute()
            DispatchQueue.main.async { completion?() }
        }
    }

    func recomputeStatsNow(dbId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        run {
            guard let supabase = self.supabase else { throw SupabaseError.notConfigured }
            _ = try await self.recomputeAndWriteStats(dbId: dbId, supabase: supabase)
            return ()
        } completion: { completion($0) }
    }

    func fetchGamesForPlayer(dbId: String, playerName: String, completion: @escaping (Result<[LegacyGame], Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.success([])) }
            return
        }
        let name = playerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            DispatchQueue.main.async { completion(.success([])) }
            return
        }
        run {
            var allRows: [GameRow] = []
            for field in ["winner1", "winner2", "loser1", "loser2"] {
                let rows: [GameRow] = try await supabase.from("games")
                    .select()
                    .eq("db_id", value: dbUUID.uuidString.lowercased())
                    .eq(field, value: name)
                    .execute()
                    .value
                allRows.append(contentsOf: rows)
            }
            var seen = Set<UUID>()
            let unique = allRows.filter { seen.insert($0.id).inserted }
            return unique.sorted { $0.game_date > $1.game_date }.map { $0.toLegacyGame() }
        } completion: { completion($0) }
    }

    func reserveDatabaseName(displayName: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let supabase = supabase else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "SupabaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please enter a name."]))) }
            return
        }
        let normalized = Self.normalizeDisplayName(trimmed)
        run {
            let existing: DisplayNameRow? = try? await supabase.from("display_names").select().eq("normalized", value: normalized).single().execute().value
            if existing != nil {
                throw NSError(domain: "SupabaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "That name is already taken. Please choose another."])
            }
            let dbId = UUID()
            try await supabase.from("databases").insert(DatabaseRow(id: dbId, display_name: trimmed, updated_at: nil)).execute()
            try await supabase.from("display_names").insert(DisplayNameRow(normalized: normalized, db_id: dbId, display_name: trimmed)).execute()
            return dbId.uuidString
        } completion: { completion($0) }
    }

    func ensureDatabase(dbId: String, displayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        run {
            let existing: DatabaseRow? = try? await supabase.from("databases").select().eq("id", value: dbUUID.uuidString.lowercased()).single().execute().value
            if existing == nil {
                try await supabase.from("databases").insert(DatabaseRow(id: dbUUID, display_name: trimmed.isEmpty ? "Unnamed" : trimmed, updated_at: nil)).execute()
            } else if !trimmed.isEmpty {
                let current = existing!.display_name
                if current == "Unnamed" || current.lowercased() == "unnamed" {
                    try await supabase.from("databases").update(DatabaseUpdate(display_name: trimmed, updated_at: Date())).eq("id", value: dbUUID.uuidString).execute()
                    let normalized = Self.normalizeDisplayName(trimmed)
                    _ = try? await supabase.from("display_names").delete().eq("db_id", value: dbUUID.uuidString).execute()
                    try await supabase.from("display_names").insert(DisplayNameRow(normalized: normalized, db_id: dbUUID, display_name: trimmed)).execute()
                }
            }
            return ()
        } completion: { completion($0) }
    }

    func fetchAdminUIDs(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let supabase = supabase else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            let row: ConfigRow? = try await supabase.from("config").select().eq("key", value: "admin_uids").single().execute().value
            return row?.value ?? []
        } completion: { completion($0) }
    }

    func fetchDefaultDatabase(completion: @escaping (Result<(dbId: String, displayName: String)?, Error>) -> Void) {
        // Supabase: no "default" database per user unless we store it in a user_prefs table. Return nil so app uses first or prompts.
        DispatchQueue.main.async { completion(.success(nil)) }
    }

    func getDatabaseDocument(dbId: String, completion: @escaping (Result<(displayName: String, isAdmin: Bool), Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            let row: DatabaseRow? = try await supabase.from("databases").select().eq("id", value: dbUUID.uuidString.lowercased()).single().execute().value
            guard let r = row else {
                throw NSError(domain: "SupabaseManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Database not found"])
            }
            let configRow: ConfigRow? = try? await supabase.from("config").select().eq("key", value: "admin_uids").single().execute().value
            let uids: [String] = configRow?.value ?? []
            let isAdmin = AuthManager.shared.uid.map { uids.contains($0) } ?? false
            return (r.display_name, isAdmin)
        } completion: { completion($0) }
    }

    func listDatabases(completion: @escaping (Result<[(id: String, displayName: String)], Error>) -> Void) {
        guard let supabase = supabase else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            let rows: [DatabaseRow] = try await supabase.from("databases").select().execute().value
            return rows.map { (id: $0.id.uuidString, displayName: $0.display_name) }
        } completion: { completion($0) }
    }

    func renameDatabase(dbId: String, currentDisplayName: String, newDisplayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "SupabaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please enter a name."]))) }
            return
        }
        let normalizedNew = Self.normalizeDisplayName(trimmed)
        let normalizedCurrent = Self.normalizeDisplayName(currentDisplayName)
        if normalizedNew == normalizedCurrent {
            DispatchQueue.main.async { completion(.success(())) }
            return
        }
        run {
            let existing: DisplayNameRow? = try? await supabase.from("display_names").select().eq("normalized", value: normalizedNew).single().execute().value
            if let e = existing, e.db_id != dbUUID {
                throw NSError(domain: "SupabaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "That name is already taken. Please choose another."])
            }
            try await supabase.from("databases").update(DatabaseUpdate(display_name: trimmed, updated_at: Date())).eq("id", value: dbUUID.uuidString).execute()
            _ = try? await supabase.from("display_names").delete().eq("normalized", value: normalizedCurrent).execute()
            try await supabase.from("display_names").insert(DisplayNameRow(normalized: normalizedNew, db_id: dbUUID, display_name: trimmed)).execute()
            return ()
        } completion: { completion($0) }
    }

    func deleteDatabase(dbId: String, displayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            try await supabase.from("games").delete().eq("db_id", value: dbUUID.uuidString).execute()
            try await supabase.from("players").delete().eq("db_id", value: dbUUID.uuidString).execute()
            try await supabase.from("stats_aggregate").delete().eq("db_id", value: dbUUID.uuidString).execute()
            try await supabase.from("activity").delete().eq("db_id", value: dbUUID.uuidString).execute()
            try await supabase.from("editor_codes").delete().eq("db_id", value: dbUUID.uuidString).execute()
            try await supabase.from("display_names").delete().eq("db_id", value: dbUUID.uuidString).execute()
            try await supabase.from("databases").delete().eq("id", value: dbUUID.uuidString).execute()
            return ()
        } completion: { completion($0) }
    }

    func createCode(dbId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            let code = UUID().uuidString.prefix(8).lowercased()
            try await supabase.from("editor_codes").insert(EditorCodeRow(code: String(code), db_id: dbUUID, created_at: nil)).execute()
            return String(code)
        } completion: { completion($0) }
    }

    func getCodeDbId(code: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let supabase = supabase else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "SupabaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please enter a code."]))) }
            return
        }
        run {
            let row: EditorCodeRow? = try await supabase.from("editor_codes").select().eq("code", value: trimmed).single().execute().value
            guard let r = row else {
                throw NSError(domain: "SupabaseManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invalid or expired code."])
            }
            _ = try? await supabase.from("editor_codes").delete().eq("code", value: trimmed).execute()
            return r.db_id.uuidString
        } completion: { completion($0) }
    }

    func fetchAllPlayers(dbId: String, editorDbId: String? = nil, completion: @escaping ([PlayerInfo]) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        run {
            guard let supabase = self.supabase else { throw SupabaseError.notConfigured }
            let recentOrder = try await self.fetchRecentPlayerNamesOrder(dbId: dbId, supabase: supabase)
            let rows: [PlayerRow] = try await supabase.from("players").select().eq("db_id", value: dbUUID.uuidString.lowercased()).execute().value
            let sorted = Self.sortPlayersByRecency(rows: rows, recentNamesOrder: recentOrder)
            let infos = sorted.map { r in
                PlayerInfo(name: r.display_name, lastPlayed: Date(), gameCount: 0, lastAddedByEditor: nil)
            }
            self.playersCacheLock.withLock {
                self.playersCache[self.playersCacheKey(dbId: dbId, editorDbId: editorDbId)] = infos
            }
            return infos
        } completion: { result in
            switch result {
            case .success(let list): completion(list)
            case .failure: completion([])
            }
        }
    }

    /// Fetch last N games and return unique player names in order of most recent appearance (first = most recent).
    private func fetchRecentPlayerNamesOrder(dbId: String, supabase: SupabaseClient) async throws -> [String] {
        guard let dbUUID = UUID(uuidString: dbId) else { return [] }
        let gameRows: [GameRow] = try await supabase.from("games")
            .select()
            .eq("db_id", value: dbUUID.uuidString.lowercased())
            .order("game_date", ascending: false)
            .limit(50)
            .execute()
            .value
        var order: [String] = []
        var seen = Set<String>()
        for g in gameRows {
            for name in [g.winner1, g.winner2, g.loser1, g.loser2] {
                let t = name.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { continue }
                let key = t.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    order.append(t)
                }
            }
        }
        return order
    }

    /// Sort player rows: those in recentNamesOrder first (in that order), then the rest alphabetically by display_name.
    private static func sortPlayersByRecency(rows: [PlayerRow], recentNamesOrder: [String]) -> [PlayerRow] {
        let recentSet = Set(recentNamesOrder.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        var sorted: [PlayerRow] = []
        var seen = Set<String>()
        for name in recentNamesOrder {
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let row = rows.first(where: { $0.display_name.trimmingCharacters(in: .whitespaces).lowercased() == key }) else { continue }
            if !seen.contains(row.display_name) {
                sorted.append(row)
                seen.insert(row.display_name)
            }
        }
        let rest = rows.filter { !seen.contains($0.display_name) }.sorted { $0.display_name.localizedCaseInsensitiveCompare($1.display_name) == .orderedAscending }
        sorted.append(contentsOf: rest)
        return sorted
    }

    func fetchPlayerRows(dbId: String, completion: @escaping (Result<[AdminPlayerRow], Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            let rows: [PlayerRow] = try await supabase.from("players")
                .select()
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .order("display_name")
                .execute()
                .value
            return rows.map { r in
                AdminPlayerRow(docId: r.doc_id, displayName: r.display_name, firstName: r.first_name, lastName: r.last_name)
            }
        } completion: { completion($0) }
    }

    func insertPlayer(dbId: String, displayName: String, firstName: String?, lastName: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "SupabaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Display name is required."]))) }
            return
        }
        let docId = Self.normalizeDisplayName(name)
        let first = firstName?.trimmingCharacters(in: .whitespaces)
        let last = lastName?.trimmingCharacters(in: .whitespaces)
        run {
            let row = PlayerRow(db_id: dbUUID, doc_id: docId, first_name: (first ?? "").isEmpty ? nil : first, last_name: (last ?? "").isEmpty ? nil : last, display_name: name)
            try await supabase.from("players").insert(row).execute()
            return ()
        } completion: { completion($0) }
    }

    func updatePlayer(dbId: String, docId: String, displayName: String, firstName: String?, lastName: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        struct PlayerUpdate: Encodable {
            let display_name: String
            let first_name: String?
            let last_name: String?
        }
        run {
            try await supabase.from("players")
                .update(PlayerUpdate(display_name: displayName, first_name: firstName, last_name: lastName))
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .eq("doc_id", value: docId)
                .execute()
            return ()
        } completion: { completion($0) }
    }

    func deletePlayer(dbId: String, docId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            try await supabase.from("players")
                .delete()
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .eq("doc_id", value: docId)
                .execute()
            return ()
        } completion: { completion($0) }
    }

    func fetchActivity(dbId: String, limit: Int = 50, completion: @escaping (Result<[ActivityEntry], Error>) -> Void) {
        guard let supabase = supabase, let dbUUID = UUID(uuidString: dbId) else {
            DispatchQueue.main.async { completion(.failure(SupabaseError.notConfigured)) }
            return
        }
        run {
            let rows: [ActivityRow] = try await supabase.from("activity")
                .select()
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .order("at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows.map { $0.toActivityEntry() }
        } completion: { completion($0) }
    }

    static func normalizeDisplayName(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = t.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "*", with: "_")
        return collapsed.isEmpty ? "unnamed" : collapsed
    }

    // MARK: - Private helpers

    private enum SupabaseError: Error {
        case notConfigured
    }

    /// Ensures a row exists in `databases`. Called e.g. when adding the first game (e.g. after entering a share code); we don't have a display name here, so the row is created as "Unnamed". The owner can rename it in the app (Databases tab → Rename) so it shows e.g. "KT" for everyone.
    private func ensureDatabaseExists(dbId: String, supabase: SupabaseClient) async throws {
        guard let dbUUID = UUID(uuidString: dbId) else { return }
        let existing: DatabaseRow? = try? await supabase.from("databases").select().eq("id", value: dbUUID.uuidString.lowercased()).single().execute().value
        if existing == nil {
            try await supabase.from("databases").insert(DatabaseRow(id: dbUUID, display_name: "Unnamed", updated_at: nil)).execute()
        }
    }

    private func ensurePlayersExist(dbId: String, names: [String], supabase: SupabaseClient) async throws {
        guard let dbUUID = UUID(uuidString: dbId) else { return }
        for name in names.map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            let docId = Self.normalizeDisplayName(name)
            let parts = name.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let first = String(parts.first ?? "")
            let last = parts.count > 1 ? String(parts[1]) : ""
            let row = PlayerRow(db_id: dbUUID, doc_id: docId, first_name: first, last_name: last, display_name: name)
            _ = try? await supabase.from("players").upsert(row).execute()
        }
    }

    private func updateStatsAfterGame(dbId: String, gameDate: Date, winner1: String, winner2: String, loser1: String, loser2: String, supabase: SupabaseClient) async throws {
        try await setStatsRecomputeRequired(dbId: dbId, supabase: supabase)
    }

    private func logActivity(dbId: String, action: String, editorDbId: String?, gameId: String?, summary: String?, supabase: SupabaseClient) async throws {
        guard let dbUUID = UUID(uuidString: dbId) else { return }
        let editorUUID = editorDbId.flatMap { UUID(uuidString: $0) }
        let gameUUID = gameId.flatMap { UUID(uuidString: $0) }
        let row = ActivityInsert(db_id: dbUUID, action: action, editor_db_id: editorUUID, game_id: gameUUID, summary: summary)
        try await supabase.from("activity").insert(row).execute()
    }

    private func setStatsRecomputeRequired(dbId: String, supabase: SupabaseClient) async throws {
        guard let dbUUID = UUID(uuidString: dbId) else { return }
        struct RecomputeFlag: Codable {
            let db_id: UUID
            let recompute_required: Bool
        }
        try await supabase.from("stats_aggregate").upsert(RecomputeFlag(db_id: dbUUID, recompute_required: true)).eq("db_id", value: dbUUID.uuidString).execute()
    }

    private func recomputeAndWriteStats(dbId: String, supabase: SupabaseClient) async throws -> (allTime: [(name: String, wins: Int, losses: Int, trueSkill: Double)], byYear: [String: [(name: String, wins: Int, losses: Int, trueSkill: Double)]]) {
        let games: [LegacyGame] = try await fetchAllGamesForStats(dbId: dbId, supabase: supabase)
        let (allTime, byYear) = computeStatsFromGames(games)
        guard let dbUUID = UUID(uuidString: dbId) else { return (allTime, byYear) }
        let allTimeEnc = Dictionary(uniqueKeysWithValues: allTime.map { p in
            let key = p.name.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "*", with: "_")
            let sigma = 25.0 / 3.0
            let mu = p.trueSkill + 3.0 * sigma
            return (key, PlayerStatValue(name: p.name, wins: p.wins, losses: p.losses, mu: mu, sigma: sigma))
        })
        var byYearEnc: [String: YearStatsValue] = [:]
        for (yr, players) in byYear {
            let playersEnc = Dictionary(uniqueKeysWithValues: players.map { p in
                let key = p.name.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "*", with: "_")
                let sigma = 25.0 / 3.0
                let mu = p.trueSkill + 3.0 * sigma
                return (key, PlayerStatValue(name: p.name, wins: p.wins, losses: p.losses, mu: mu, sigma: sigma))
            })
            byYearEnc[yr] = YearStatsValue(players: playersEnc)
        }
        let row = StatsAggregateRow(db_id: dbUUID, recompute_required: false, all_time: allTimeEnc, by_year: byYearEnc, years: ["All"] + byYear.keys.sorted(by: >), updated_at: Date())
        try await supabase.from("stats_aggregate").upsert(row).eq("db_id", value: dbUUID.uuidString).execute()
        return (allTime, byYear)
    }

    private func fetchAllGamesForStats(dbId: String, supabase: SupabaseClient) async throws -> [LegacyGame] {
        guard let dbUUID = UUID(uuidString: dbId) else { return [] }
        var all: [GameRow] = []
        var offset = 0
        let pageSize = 300
        while true {
            let rows: [GameRow] = try await supabase.from("games")
                .select()
                .eq("db_id", value: dbUUID.uuidString.lowercased())
                .order("game_date", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            all.append(contentsOf: rows)
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all.map { $0.toLegacyGame() }
    }

    private func computeStatsFromGames(_ games: [LegacyGame]) -> (allTime: [(name: String, wins: Int, losses: Int, trueSkill: Double)], byYear: [String: [(name: String, wins: Int, losses: Int, trueSkill: Double)]]) {
        // Reuse same logic as FirebaseManager - call into TrueSkillRatingSystem
        var wins: [String: Int] = [:]
        var losses: [String: Int] = [:]
        var byYearWins: [String: [String: Int]] = [:]
        var byYearLosses: [String: [String: Int]] = [:]
        let calendar = Calendar.current
        for g in games {
            let w1 = g.winner1.trimmingCharacters(in: .whitespaces)
            let w2 = g.winner2.trimmingCharacters(in: .whitespaces)
            let l1 = g.loser1.trimmingCharacters(in: .whitespaces)
            let l2 = g.loser2.trimmingCharacters(in: .whitespaces)
            guard !w1.isEmpty, !w2.isEmpty, !l1.isEmpty, !l2.isEmpty else { continue }
            for n in [w1, w2] { wins[n, default: 0] += 1 }
            for n in [l1, l2] { losses[n, default: 0] += 1 }
            let yearStr = String(calendar.component(.year, from: g.date))
            for n in [w1, w2] { byYearWins[yearStr, default: [:]][n, default: 0] += 1 }
            for n in [l1, l2] { byYearLosses[yearStr, default: [:]][n, default: 0] += 1 }
        }
        let validGames = games.filter { g in
            let w1 = g.winner1.trimmingCharacters(in: .whitespaces)
            let w2 = g.winner2.trimmingCharacters(in: .whitespaces)
            let l1 = g.loser1.trimmingCharacters(in: .whitespaces)
            let l2 = g.loser2.trimmingCharacters(in: .whitespaces)
            return !w1.isEmpty && !w2.isEmpty && !l1.isEmpty && !l2.isEmpty
        }
        let sortedGames = validGames.sorted { $0.date < $1.date }
        let trueSkillAll = TrueSkillRatingSystem.calculateRatings(from: sortedGames)
        let allPlayers = Set(wins.keys).union(losses.keys)
        let allTime: [(name: String, wins: Int, losses: Int, trueSkill: Double)] = allPlayers.map { name in
            (name: name, wins: wins[name] ?? 0, losses: losses[name] ?? 0, trueSkill: trueSkillAll[name]?.exposed ?? 0)
        }
        var byYear: [String: [(name: String, wins: Int, losses: Int, trueSkill: Double)]] = [:]
        for yearStr in Set(byYearWins.keys).union(byYearLosses.keys) {
            let yearGames = validGames.filter { String(calendar.component(.year, from: $0.date)) == yearStr }
            let ts = TrueSkillRatingSystem.calculateRatings(from: yearGames.sorted { $0.date < $1.date })
            let players = Set(byYearWins[yearStr, default: [:]].keys).union(byYearLosses[yearStr, default: [:]].keys)
            byYear[yearStr] = players.map { name in
                (name: name, wins: byYearWins[yearStr]?[name] ?? 0, losses: byYearLosses[yearStr]?[name] ?? 0, trueSkill: ts[name]?.exposed ?? 0)
            }
        }
        return (allTime, byYear)
    }

    private func encodeStatsPlayers(_ list: [(name: String, wins: Int, losses: Int, trueSkill: Double)]) -> [String: Any] {
        var map: [String: Any] = [:]
        for p in list {
            let key = p.name.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "*", with: "_")
            let sigma = 25.0 / 3.0
            let mu = p.trueSkill + 3.0 * sigma
            map[key] = ["name": p.name, "wins": p.wins, "losses": p.losses, "mu": mu, "sigma": sigma]
        }
        return map
    }

    private func parseStatsPlayers(_ players: [String: Any]) -> [(name: String, wins: Int, losses: Int, trueSkill: Double)] {
        players.compactMap { _, v -> (name: String, wins: Int, losses: Int, trueSkill: Double)? in
            guard let map = v as? [String: Any], let name = map["name"] as? String else { return nil }
            let wins = (map["wins"] as? Int) ?? (map["wins"] as? Int64).map { Int($0) } ?? 0
            let losses = (map["losses"] as? Int) ?? (map["losses"] as? Int64).map { Int($0) } ?? 0
            let mu = (map["mu"] as? Double) ?? 25.0
            let sigma = (map["sigma"] as? Double) ?? (25.0 / 3.0)
            return (name: name, wins: wins, losses: losses, trueSkill: mu - 3.0 * sigma)
        }
    }

    private func parseStatsByYear(_ byYear: [String: Any], year: String) -> [(name: String, wins: Int, losses: Int, trueSkill: Double)]? {
        guard let yearData = byYear[year] as? [String: Any], let playersMap = yearData["players"] as? [String: Any] else { return nil }
        return parseStatsPlayers(playersMap)
    }
}

// MARK: - Row types (Codable for Supabase)

private struct DatabaseRow: Codable {
    let id: UUID
    let display_name: String
    let updated_at: Date?
}

private struct DatabaseUpdate: Codable {
    let display_name: String
    let updated_at: Date
}

private struct DisplayNameRow: Codable {
    let normalized: String
    let db_id: UUID
    let display_name: String
}

private struct GameRow: Codable {
    let id: UUID
    let db_id: UUID
    let game_date: Date
    let winner1: String
    let winner2: String
    let winner_score: Int
    let loser1: String
    let loser2: String
    let loser_score: Int
    let comments: String?
    let updated_at: Date?
    let entered_timezone: String?
    let updated_by: String?
    let editor_db_id: UUID?

    func toLegacyGame() -> LegacyGame {
        LegacyGame(
            id: abs(id.hashValue) & 0x7FFF_FFFF,
            date: game_date,
            winner1: winner1,
            winner2: winner2,
            winnerScore: winner_score,
            loser1: loser1,
            loser2: loser2,
            loserScore: loser_score,
            comment: comments ?? "",
            recordName: id.uuidString
        )
    }
}

private struct GameUpdate: Codable {
    let winner1: String
    let winner2: String
    let winner_score: Int
    let loser1: String
    let loser2: String
    let loser_score: Int
    let comments: String
    let updated_at: Date
}

private struct PlayerRow: Codable {
    let db_id: UUID
    let doc_id: String
    let first_name: String?
    let last_name: String?
    let display_name: String
}

private struct StatsAggregateRow: Codable {
    let db_id: UUID
    let recompute_required: Bool?
    let all_time: [String: PlayerStatValue]?
    let by_year: [String: YearStatsValue]?
    let years: [String]?
    let updated_at: Date?

    var allTimeDict: [String: Any]? {
        guard let a = all_time else { return nil }
        return a.mapValues { ["name": $0.name, "wins": $0.wins, "losses": $0.losses, "mu": $0.mu, "sigma": $0.sigma] }
    }
    var byYearDict: [String: Any]? {
        guard let b = by_year else { return nil }
        return b.mapValues { ["players": $0.players.mapValues { ["name": $0.name, "wins": $0.wins, "losses": $0.losses, "mu": $0.mu, "sigma": $0.sigma] }] }
    }
}

private struct PlayerStatValue: Codable {
    let name: String
    let wins: Int
    let losses: Int
    let mu: Double
    let sigma: Double
}

private struct YearStatsValue: Codable {
    let players: [String: PlayerStatValue]
}

private struct ActivityRow: Codable {
    let id: UUID
    let db_id: UUID
    let action: String
    let editor_db_id: UUID?
    let game_id: UUID?
    let summary: String?
    let at: Date

    func toActivityEntry() -> ActivityEntry {
        ActivityEntry(
            id: id.uuidString,
            action: action,
            at: at,
            editorDbId: editor_db_id?.uuidString ?? "",
            gameId: game_id?.uuidString,
            summary: summary
        )
    }
}

private struct ActivityInsert: Encodable {
    let db_id: UUID
    let action: String
    let editor_db_id: UUID?
    let game_id: UUID?
    let summary: String?
}

private struct EditorCodeRow: Codable {
    let code: String
    let db_id: UUID
    let created_at: Date?
}

private struct ConfigRow: Codable {
    let key: String
    let value: [String]
}

