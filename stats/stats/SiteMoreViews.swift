import SwiftUI
import Combine
import PhotosUI
import Speech
import AVFoundation

struct SiteMoreView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @ObservedObject private var theme = SiteTheme.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if auth.isLoggedIn {
                        Text("Signed in as \(auth.username ?? "")")
                        if auth.isAdmin { Text("Admin").foregroundStyle(.orange) }
                        Button("Log out") { Task { await auth.logout() } }
                    } else {
                        NavigationLink("Login") { LoginView() }
                    }
                    Button(theme.isDark ? "Light mode" : "Dark mode") { theme.toggle() }
                }
                Section("Browse") {
                    NavigationLink("Players") { SitePlayersView() }
                    NavigationLink("Player network") { SiteNetworkView() }
                    NavigationLink("Tournaments") { SiteTournamentsView() }
                    NavigationLink("Volleyball") { SiteVolleyballView() }
                }
                if auth.isLoggedIn {
                    Section("Create") {
                        NavigationLink("AI Summary") { SiteAISummaryView() }
                        NavigationLink("AI Recaps") { SiteRecapsView() }
                        NavigationLink("Create Flyer") { SiteFlyerView() }
                        NavigationLink("Add doubles by voice") { SiteVoiceAddView() }
                    }
                }
                if auth.isAdmin {
                    Section("Admin") {
                        NavigationLink("Admin dashboard") { SiteAdminView() }
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

struct SitePlayersView: View {
    @State private var players: [SitePlayer] = []
    @State private var search = ""
    @State private var error: String?
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var newName = ""

    var body: some View {
        List {
            if auth.isLoggedIn {
                Section("Add player") {
                    HStack {
                        TextField("Full name", text: $newName)
                        Button("Add") {
                            Task {
                                do {
                                    try await PythonAnywhereClient.shared.addPlayer(fullName: newName)
                                    newName = ""
                                    await load()
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(filtered) { p in
                NavigationLink {
                    SiteEditPlayerView(player: p)
                } label: {
                    HStack {
                        AsyncImage(url: URL(string: p.photoUrl ?? "")) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 36, height: 36).clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text("\(p.games ?? 0) games").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Players")
        .task { await load() }
        .refreshable { await load() }
    }

    private var filtered: [SitePlayer] {
        let q = search.lowercased()
        if q.isEmpty { return players }
        return players.filter { $0.name.lowercased().contains(q) }
    }

    private func load() async {
        do { players = try await PythonAnywhereClient.shared.players() }
        catch { self.error = error.localizedDescription }
    }
}

struct SiteEditPlayerView: View {
    var player: SitePlayer
    @State private var name: String
    @State private var nickname: String
    @State private var email: String
    @State private var height: String
    @State private var dob: String
    @State private var error: String?
    @State private var picker: PhotosPickerItem?
    @ObservedObject private var auth = SiteAuthManager.shared

    init(player: SitePlayer) {
        self.player = player
        _name = State(initialValue: player.name)
        _nickname = State(initialValue: player.nickname ?? "")
        _email = State(initialValue: player.email ?? "")
        _height = State(initialValue: player.height ?? "")
        _dob = State(initialValue: player.dateOfBirth ?? "")
    }

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            AsyncImage(url: URL(string: player.photoUrl ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: { Color.gray.opacity(0.2) }
            .frame(height: 160).clipped()
            if auth.isLoggedIn {
                PhotosPicker("Upload face photo", selection: $picker, matching: .images)
            }
            TextField("Name", text: $name)
            TextField("Nickname", text: $nickname)
            TextField("Email", text: $email)
            TextField("Height", text: $height)
            TextField("Date of birth", text: $dob)
            if auth.isLoggedIn {
                Button("Save") { Task { await save() } }
            }
            NavigationLink("Doubles stats") {
                SitePlayerDetailView(name: player.name, year: String(Calendar.current.component(.year, from: Date())), section: .doubles)
            }
        }
        .navigationTitle(player.name)
        .onChange(of: picker) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                do {
                    try await PythonAnywhereClient.shared.uploadPlayerPhoto(name: player.name, imageData: data, filename: "photo.jpg")
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func save() async {
        do {
            if name != player.name {
                try await PythonAnywhereClient.shared.renamePlayer(oldName: player.name, newName: name)
            }
            try await PythonAnywhereClient.shared.updatePlayerInfo([
                "player_name": name,
                "nickname": nickname,
                "email": email,
                "height": height,
                "birthday": dob,
            ])
        } catch { self.error = error.localizedDescription }
    }
}

struct SiteNetworkView: View {
    @State private var payload: NetworkPayload?
    @State private var year = String(Calendar.current.component(.year, from: Date()))
    @State private var error: String?

    var body: some View {
        VStack {
            if let error { Text(error).foregroundStyle(.red) }
            if let p = payload {
                Picker("Year", selection: $year) {
                    ForEach(p.allYears, id: \.self) { Text($0 == "All years" ? "All" : $0).tag($0) }
                }
                Canvas { context, size in
                    let nodes = p.network.nodes.prefix(40)
                    let n = max(nodes.count, 1)
                    for (i, node) in nodes.enumerated() {
                        let angle = Double(i) / Double(n) * .pi * 2
                        let r = min(size.width, size.height) * 0.38
                        let x = size.width / 2 + r * cos(angle)
                        let y = size.height / 2 + r * sin(angle)
                        let rect = CGRect(x: x - 18, y: y - 18, width: 36, height: 36)
                        context.fill(Path(ellipseIn: rect), with: .color(.orange.opacity(0.8)))
                        context.draw(Text(node.label ?? node.id).font(.system(size: 8)), at: CGPoint(x: x, y: y + 28))
                    }
                    for edge in p.network.partnerEdges.prefix(80) {
                        guard let i1 = nodes.firstIndex(where: { $0.id == edge.source }),
                              let i2 = nodes.firstIndex(where: { $0.id == edge.target }) else { continue }
                        let a1 = Double(i1) / Double(n) * .pi * 2
                        let a2 = Double(i2) / Double(n) * .pi * 2
                        let r = min(size.width, size.height) * 0.38
                        var path = Path()
                        path.move(to: CGPoint(x: size.width / 2 + r * cos(a1), y: size.height / 2 + r * sin(a1)))
                        path.addLine(to: CGPoint(x: size.width / 2 + r * cos(a2), y: size.height / 2 + r * sin(a2)))
                        context.stroke(path, with: .color(.white.opacity(0.25)), lineWidth: 1)
                    }
                }
                .frame(minHeight: 360)
                List(p.network.partnerEdges.prefix(50)) { e in
                    Text("\(e.source) — \(e.target)  \(e.games ?? 0) games")
                }
            }
        }
        .navigationTitle("Network")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SiteCopyLinkButton(url: SitePublicLink.network(year: year))
            }
        }
        .task(id: year) { await load() }
    }

    private func load() async {
        do { payload = try await PythonAnywhereClient.shared.network(year: year) }
        catch { self.error = error.localizedDescription }
    }
}

struct SiteTournamentsView: View {
    @State private var items: [Tournament] = []
    @State private var name = ""
    @State private var place = ""
    @State private var team = ""
    @State private var location = ""
    @State private var dateStr = ""
    @State private var error: String?
    @ObservedObject private var auth = SiteAuthManager.shared

    var body: some View {
        List {
            if auth.isLoggedIn {
                Section("Add") {
                    TextField("Tournament name", text: $name)
                    TextField("Place (1st, 2nd…)", text: $place)
                    TextField("Team", text: $team)
                    TextField("Location", text: $location)
                    TextField("Date YYYY-MM-DD", text: $dateStr)
                    Button("Save") { Task { await add() } }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { t in
                VStack(alignment: .leading) {
                    Text(t.tournamentName ?? "").font(.headline)
                    Text("\(t.tournamentDate ?? "") · \(t.place ?? "") · \(t.team ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(t.location ?? "").font(.caption)
                }
            }
        }
        .navigationTitle("Tournaments")
        .task { await load() }
    }

    private func load() async {
        do { items = try await PythonAnywhereClient.shared.tournaments() }
        catch { self.error = error.localizedDescription }
    }

    private func add() async {
        do {
            try await PythonAnywhereClient.shared.addTournament([
                "tournament_name": name, "place": place, "team": team,
                "location": location, "tournament_date": dateStr,
            ])
            name = ""; place = ""; team = ""; location = ""; dateStr = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct SiteVolleyballView: View {
    @State private var payload: OtherStatsPayload?
    @State private var year = String(Calendar.current.component(.year, from: Date()))

    var body: some View {
        ScrollView {
            if let p = payload {
                ForEach(p.gameCards) { card in
                    RankingTable(title: card.gameName, rows: card.stats, showRating: false, year: year, section: .other)
                }
            }
        }
        .navigationTitle("Volleyball")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SiteCopyLinkButton(url: SitePublicLink.volleyball(year: year))
            }
        }
        .task {
            payload = try? await PythonAnywhereClient.shared.volleyballStats(year: year)
        }
    }
}

struct AISummaryPick: Identifiable, Hashable {
    var id: String
    var dateRaw: String?
    var subtitle: String?
    var winners: String
    var losers: String
    var winnerScore: Int?
    var loserScore: Int?

    var dayKey: String {
        if let date = DoublesGame.parseDate(dateRaw) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }
        return String((dateRaw ?? "").prefix(10))
    }
}

struct SiteAISummaryView: View {
    @State private var gameType = "doubles"
    @State private var query = ""
    @State private var games: [AISummaryPick] = []
    @State private var selected: Set<String> = []
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var shareURL: URL?
    @State private var loading = false
    @State private var generating = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $gameType) {
                Text("Doubles").tag("doubles")
                Text("Vollis").tag("vollis")
                Text("Other").tag("other")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            TextField("Search players or games", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.top, 10)
                .onSubmit { Task { await runSearch(query) } }

            HStack {
                Button("Select latest day") { selectLatestDay() }
                Button("Clear") { selected.removeAll() }
                Spacer()
                Text("\(selected.count) selected")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let banner {
                SiteAddBanner(text: banner, isError: bannerIsError)
                    .padding(.horizontal)
            }
            if let shareURL {
                HStack(spacing: 12) {
                    ShareLink(item: shareURL)
                    SiteCopyLinkButton(url: shareURL)
                    Link("Open", destination: shareURL)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if loading {
                ProgressView().padding()
            }

            List(games) { game in
                Button { toggle(game.id) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selected.contains(game.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(game.id) ? SiteAddAccent.orange : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if let date = DoublesGame.parseDate(game.dateRaw) {
                                    Text(date, style: .date)
                                } else if let raw = game.dateRaw, !raw.isEmpty {
                                    Text(raw)
                                }
                                if let subtitle = game.subtitle, !subtitle.isEmpty {
                                    Text("· \(subtitle)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack {
                                Text(game.winners).foregroundStyle(.green)
                                Spacer()
                                if let s = game.winnerScore { Text("\(s)").foregroundStyle(.green) }
                            }
                            HStack {
                                Text(game.losers).foregroundStyle(.red)
                                Spacer()
                                if let s = game.loserScore { Text("\(s)").foregroundStyle(.red) }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)

            SiteAddActionButton(
                title: generating ? "Creating recap…" : "Create recap",
                filled: true,
                disabled: generating || selected.isEmpty
            ) {
                Task { await generate() }
            }
            .padding()
        }
        .navigationTitle("AI Summary")
        .task(id: gameType) {
            query = ""
            await loadRecent()
        }
        .onChange(of: query) { _, q in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await runSearch(q)
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func selectLatestDay() {
        guard let day = games.first?.dayKey, !day.isEmpty else { return }
        selected = Set(games.filter { $0.dayKey == day }.map(\.id))
    }

    private func loadRecent() async {
        loading = true
        banner = nil
        shareURL = nil
        selected = []
        let year = String(Calendar.current.component(.year, from: Date()))
        do {
            switch gameType {
            case "vollis":
                let rows = try await PythonAnywhereClient.shared.vollisGames(year: year).games
                games = rows.map { g in
                    AISummaryPick(
                        id: String(g.id),
                        dateRaw: g.gameDate,
                        winners: g.winner ?? "",
                        losers: g.loser ?? "",
                        winnerScore: g.winnerScore,
                        loserScore: g.loserScore
                    )
                }
            case "other":
                let rows = try await PythonAnywhereClient.shared.otherGames(year: year).games
                games = rows.map { g in
                    AISummaryPick(
                        id: String(g.id),
                        dateRaw: g.gameDateOnly ?? g.gameDate,
                        subtitle: g.gameName,
                        winners: g.displayWinners.joined(separator: ", "),
                        losers: g.displayLosers.joined(separator: ", "),
                        winnerScore: g.winnerScore,
                        loserScore: g.loserScore
                    )
                }
            default:
                let rows = try await PythonAnywhereClient.shared.doublesGames(year: year).games
                games = rows.prefix(40).map { g in
                    AISummaryPick(
                        id: String(g.id),
                        dateRaw: g.gameDate,
                        winners: [g.winner1, g.winner2].compactMap { $0 }.joined(separator: " & "),
                        losers: [g.loser1, g.loser2].compactMap { $0 }.joined(separator: " & "),
                        winnerScore: g.winnerScore,
                        loserScore: g.loserScore
                    )
                }
            }
            if gameType != "doubles" {
                games = Array(games.prefix(40))
            }
            selectLatestDay()
        } catch {
            banner = error.localizedDescription
            bannerIsError = true
            games = []
        }
        loading = false
    }

    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            await loadRecent()
            return
        }
        loading = true
        let rows = (try? await PythonAnywhereClient.shared.searchAIGames(q: q, gameType: gameType)) ?? []
        games = rows.compactMap(Self.pick(fromSearch:))
        selected = []
        loading = false
    }

    private func generate() async {
        generating = true
        banner = nil
        shareURL = nil
        bannerIsError = false
        do {
            let jobId = try await PythonAnywhereClient.shared.generateAISummary(
                gameType: gameType,
                gameIds: Array(selected)
            )
            banner = "Creating recap…"
            if let url = await waitForRecap(jobId: jobId) {
                shareURL = url
                banner = "Recap ready"
            } else {
                banner = "Recap queued. Check Recaps in a minute."
            }
        } catch {
            banner = error.localizedDescription
            bannerIsError = true
        }
        generating = false
    }

    private func waitForRecap(jobId: Int) async -> URL? {
        for i in 0..<30 {
            if i > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            guard let job = try? await PythonAnywhereClient.shared.aiJob(id: jobId) else { continue }
            let status = (job["status"] as? String ?? "").lowercased()
            if status == "failed" || status == "error" {
                banner = (job["error"] as? String) ?? "Recap failed"
                bannerIsError = true
                return nil
            }
            if let share = job["share_id"] as? String, !share.isEmpty {
                return SitePublicLink.recap(share)
            }
            if status == "completed" || status == "done" {
                return nil
            }
        }
        return nil
    }

    private static func pick(fromSearch row: [String: Any]) -> AISummaryPick? {
        let id = row["id"] as? Int ?? Int("\(row["id"] ?? "")")
        guard let id else { return nil }
        return AISummaryPick(
            id: String(id),
            dateRaw: row["date"] as? String,
            subtitle: row["game_name"] as? String,
            winners: names(row["winners"] ?? row["winner_names"]),
            losers: names(row["losers"] ?? row["loser_names"]),
            winnerScore: intValue(row["winner_score"]),
            loserScore: intValue(row["loser_score"])
        )
    }

    private static func names(_ raw: Any?) -> String {
        if let s = raw as? String { return s }
        if let a = raw as? [String] { return a.filter { !$0.isEmpty }.joined(separator: ", ") }
        if let a = raw as? [[String: Any]] {
            return a.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return ""
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let s = raw as? String { return Int(s) }
        return nil
    }
}

struct SiteRecapsView: View {
    @State private var items: [RecapItem] = []
    var body: some View {
        List(items) { r in
            VStack(alignment: .leading) {
                Text(r.headline ?? "Recap").font(.headline)
                if let url = r.shareUrl, let u = URL(string: url) {
                    HStack {
                        ShareLink(item: u)
                        SiteCopyLinkButton(url: u)
                        Link("Open", destination: u)
                    }
                }
                if let img = r.heroImageUrl, let u = URL(string: img) {
                    AsyncImage(url: u) { i in i.resizable().scaledToFit() } placeholder: { ProgressView() }
                }
            }
        }
        .navigationTitle("AI Recaps")
        .task { items = (try? await PythonAnywhereClient.shared.recaps()) ?? [] }
    }
}

struct SiteFlyerView: View {
    @State private var playersText = ""
    @State private var location = ""
    @State private var eventDate = ""
    @State private var eventTime = ""
    @State private var message: String?

    var body: some View {
        Form {
            TextField("Players (comma-separated)", text: $playersText)
            TextField("Location", text: $location)
            TextField("Date YYYY-MM-DD", text: $eventDate)
            TextField("Time (e.g. 5:00 PM)", text: $eventTime)
            Button("Create flyer") {
                Task {
                    let players = playersText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    do {
                        let id = try await PythonAnywhereClient.shared.createFlyer([
                            "players": players,
                            "game_type": "doubles",
                            "event_date": eventDate,
                            "event_time": eventTime,
                            "location": location,
                        ])
                        message = "Queued flyer job #\(id)"
                    } catch { message = error.localizedDescription }
                }
            }
            if let message { Text(message) }
        }
        .navigationTitle("Flyer")
    }
}

struct SiteVoiceAddView: View {
    @StateObject private var capture = VoiceCapture()
    @State private var parsed: [String: Any] = [:]
    @State private var status = ""

    var body: some View {
        Form {
            Text("Speak a result like “Kyle and Aaron beat Dan and Ryan 21 15”.")
            TextEditor(text: $capture.transcript).frame(minHeight: 80)
            Button(capture.isRecording ? "Stop recording" : "Record") {
                Task { await capture.toggle() }
            }
            Button("Parse") { Task { await parse() } }
            if !parsed.isEmpty {
                Text(String(describing: parsed)).font(.caption)
                Button("Save game") { Task { await save() } }
            }
            Text(status.isEmpty ? capture.status : status).foregroundStyle(.secondary)
        }
        .navigationTitle("Voice")
        .onAppear {
            SFSpeechRecognizer.requestAuthorization { _ in }
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
    }

    private func parse() async {
        do {
            parsed = try await PythonAnywhereClient.shared.parseVoice(transcript: capture.transcript)
            status = "Parsed."
        } catch { status = error.localizedDescription }
    }

    private func save() async {
        guard let w1 = parsed["winner1"] as? String, let w2 = parsed["winner2"] as? String,
              let l1 = parsed["loser1"] as? String, let l2 = parsed["loser2"] as? String else { return }
        let ws = parsed["winner_score"] as? Int ?? Int("\(parsed["winner_score"] ?? "")") ?? 0
        let ls = parsed["loser_score"] as? Int ?? Int("\(parsed["loser_score"] ?? "")") ?? 0
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        do {
            _ = try await PythonAnywhereClient.shared.createDoubles([
                "game_date": df.string(from: Date()),
                "winner1": w1, "winner2": w2, "loser1": l1, "loser2": l2,
                "winner_score": ws, "loser_score": ls,
                "entered_timezone": TimeZone.current.identifier,
            ])
            status = "Saved."
        } catch { status = error.localizedDescription }
    }
}

@MainActor
final class VoiceCapture: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var status = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var hasTap = false

    func toggle() async {
        if isRecording {
            stop()
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition isn’t available. Type the result instead."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            if hasTap {
                input.removeTap(onBus: 0)
                hasTap = false
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            isRecording = true
            status = "Listening…"
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.transcript = result.bestTranscription.formattedString
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    Task { @MainActor in self.stop() }
                }
            }
        } catch {
            status = error.localizedDescription
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
        }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        if status == "Listening…" { status = "Stopped." }
    }
}

struct SiteAdminView: View {
    @State private var overview: [String: Any] = [:]
    @State private var activity: [[String: Any]] = []
    @State private var message: String?
    @State private var newUser = ""
    @State private var newPass = ""

    var body: some View {
        List {
            if let message { Text(message) }
            Section("Overview") {
                Text(String(describing: overview["counts"] ?? "—"))
                Text("DB \(overview["db_size_mb"] ?? "—") MB")
            }
            Section("Actions") {
                Button("Backup database") { Task { try? await PythonAnywhereClient.shared.adminBackup(); message = "Backup started" } }
                Button("Clear stats cache") { Task { try? await PythonAnywhereClient.shared.adminClearCache(); message = "Cache cleared" } }
                Button("Send test email") { Task { do { try await PythonAnywhereClient.shared.adminTestEmail(); message = "Email sent" } catch { message = error.localizedDescription } } }
            }
            Section("Add user") {
                TextField("Username", text: $newUser)
                SecureField("Password", text: $newPass)
                Button("Create") {
                    Task {
                        do {
                            try await PythonAnywhereClient.shared.adminAddUser(username: newUser, password: newPass, isAdmin: false)
                            message = "User created"
                        } catch { message = error.localizedDescription }
                    }
                }
            }
            Section("Activity") {
                ForEach(activity.indices, id: \.self) { i in
                    let e = activity[i]
                    VStack(alignment: .leading) {
                        Text("\(e["username"] ?? "") · \(e["action"] ?? "")").font(.subheadline)
                        Text("\(e["summary"] ?? "")").font(.caption).foregroundStyle(.secondary)
                        if let id = e["id"] as? Int {
                            Button("Undo") {
                                Task {
                                    do { try await PythonAnywhereClient.shared.adminUndo(id: id); message = "Undone" }
                                    catch { message = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Admin")
        .task {
            overview = (try? await PythonAnywhereClient.shared.adminOverview()) ?? [:]
            let act = (try? await PythonAnywhereClient.shared.adminActivity()) ?? [:]
            activity = act["entries"] as? [[String: Any]] ?? []
        }
    }
}
