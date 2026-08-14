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

struct SiteAISummaryView: View {
    @State private var query = ""
    @State private var gameType = "doubles"
    @State private var results: [[String: Any]] = []
    @State private var selected: Set<String> = []
    @State private var style = "default"
    @State private var custom = ""
    @State private var message: String?
    @State private var jobId: Int?

    var body: some View {
        Form {
            Picker("Type", selection: $gameType) {
                Text("Doubles").tag("doubles")
                Text("Vollis").tag("vollis")
                Text("Other").tag("other")
            }
            TextField("Search games", text: $query)
            Button("Search") { Task { await search() } }
            ForEach(results.indices, id: \.self) { i in
                let row = results[i]
                let id = "\(row["id"] ?? i)"
                Button {
                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                        Text(String(describing: row["summary"] ?? row["label"] ?? id)).font(.caption)
                    }
                }
            }
            TextField("Style", text: $style)
            TextField("Custom prompt", text: $custom, axis: .vertical)
            Button("Generate recap") { Task { await generate() } }
            if let message { Text(message) }
            if let jobId { Text("Job #\(jobId)") }
        }
        .navigationTitle("AI Summary")
    }

    private func search() async {
        results = (try? await PythonAnywhereClient.shared.searchAIGames(q: query, gameType: gameType)) ?? []
    }

    private func generate() async {
        do {
            jobId = try await PythonAnywhereClient.shared.generateAISummary(
                gameType: gameType, gameIds: Array(selected), promptStyle: style, customPrompt: custom
            )
            message = "Queued recap job."
        } catch { message = error.localizedDescription }
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
    enum Field: Hashable { case player, location, details }

    @State private var gameType = "doubles"
    @State private var playerQuery = ""
    @State private var selected: [String] = []
    @State private var recent: [String] = []
    @State private var allPlayers: [String] = []
    @State private var location = ""
    @State private var eventDate = Date()
    @State private var eventTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var imageDetails = ""
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var shareURL: URL?
    @State private var saving = false
    @FocusState private var focused: Field?

    private let timePresets = [16, 17, 18, 19, 20]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let banner {
                    SiteAddBanner(text: banner, isError: bannerIsError)
                }
                if let shareURL {
                    HStack(spacing: 12) {
                        ShareLink(item: shareURL)
                        SiteCopyLinkButton(url: shareURL)
                        Link("Open", destination: shareURL)
                    }
                }

                Picker("Game", selection: $gameType) {
                    Text("Doubles").tag("doubles")
                    Text("Vollis").tag("vollis")
                    Text("Other").tag("other")
                }
                .pickerStyle(.segmented)

                Text("Who’s playing")
                    .font(.subheadline.weight(.semibold))
                if !selected.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selected, id: \.self) { name in
                                Button { removePlayer(name) } label: {
                                    HStack(spacing: 6) {
                                        Text(name)
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(SiteAddAccent.orange.opacity(0.2))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                SiteAddTextRow(label: "Search players", text: $playerQuery, field: .player, focus: $focused, submit: .done, onSubmit: {
                    addTypedPlayer()
                })
                if focused == .player && !playerQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    SiteAddSuggestionList(names: suggestions) { name in
                        addPlayer(name)
                    }
                }
                if !recentAvailable.isEmpty {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentAvailable, id: \.self) { name in
                                Button { addPlayer(name) } label: {
                                    Text(name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.secondarySystemFill))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        dateChip("Today", date: Date())
                        dateChip("Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
                    }
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Time")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(timePresets, id: \.self) { hour in
                            let selectedHour = Calendar.current.component(.hour, from: eventTime) == hour
                            Button { setTime(hour: hour) } label: {
                                Text(timeLabel(hour))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedHour ? SiteAddAccent.orange : Color(.secondarySystemFill))
                                    .foregroundStyle(selectedHour ? Color.black : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    DatePicker("Time", selection: $eventTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                }

                SiteAddTextRow(label: "Location", text: $location, field: .location, focus: $focused, submit: .next, onSubmit: {
                    focused = .details
                })

                VStack(alignment: .leading, spacing: 8) {
                    Text("AI image details")
                        .font(.subheadline.weight(.semibold))
                    Text("Optional notes for the flyer image, like sunset, backyard, bring a friend…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if imageDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Image prompt details")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        TextEditor(text: $imageDetails)
                            .focused($focused, equals: .details)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: 100)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focused == .details ? SiteAddAccent.orange : Color.clear, lineWidth: 2)
                    )
                }

                SiteAddActionButton(
                    title: saving ? "Creating flyer…" : "Create flyer",
                    filled: true,
                    disabled: saving || selected.isEmpty || location.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task { await create() }
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Flyer")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task { await loadPlayers() }
        .onChange(of: gameType) { _, _ in
            Task { await loadRecent() }
        }
    }

    private var suggestions: [String] {
        siteFilterPlayers(allPlayers, query: playerQuery, excluding: selected)
    }

    private var recentAvailable: [String] {
        siteFilterPlayers(recent, query: "", excluding: selected, limit: 16)
    }

    private func dateChip(_ title: String, date: Date) -> some View {
        let same = Calendar.current.isDate(eventDate, inSameDayAs: date)
        return Button { eventDate = date } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(same ? SiteAddAccent.orange : Color(.secondarySystemFill))
                .foregroundStyle(same ? Color.black : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func timeLabel(_ hour: Int) -> String {
        hour < 12 ? "\(hour) AM" : hour == 12 ? "12 PM" : "\(hour - 12) PM"
    }

    private func setTime(hour: Int) {
        eventTime = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: eventTime) ?? eventTime
    }

    private func addPlayer(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !selected.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { return }
        selected.append(n)
        playerQuery = ""
        focused = .player
    }

    private func addTypedPlayer() {
        let q = playerQuery.trimmingCharacters(in: .whitespaces)
        if let match = suggestions.first {
            addPlayer(match)
        } else if !q.isEmpty {
            addPlayer(q)
        }
    }

    private func removePlayer(_ name: String) {
        selected.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func loadPlayers() async {
        if let rows = try? await PythonAnywhereClient.shared.players() {
            allPlayers = rows.sorted { ($0.games ?? 0) > ($1.games ?? 0) }.map(\.name)
        }
        await loadRecent()
        if allPlayers.isEmpty { allPlayers = recent }
    }

    private func loadRecent() async {
        switch gameType {
        case "vollis":
            recent = (try? await PythonAnywhereClient.shared.vollisPlayers()) ?? recent
        default:
            recent = (try? await PythonAnywhereClient.shared.doublesPlayers()) ?? recent
        }
        if allPlayers.isEmpty { allPlayers = recent }
        else {
            let extra = recent.filter { name in
                !allPlayers.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
            allPlayers = extra + allPlayers
        }
    }

    private func create() async {
        saving = true
        banner = nil
        shareURL = nil
        bannerIsError = false
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "h:mm a"
        do {
            let id = try await PythonAnywhereClient.shared.createFlyer([
                "players": selected,
                "game_type": gameType,
                "event_date": dateFmt.string(from: eventDate),
                "event_time": timeFmt.string(from: eventTime),
                "location": location.trimmingCharacters(in: .whitespaces),
                "image_details": imageDetails.trimmingCharacters(in: .whitespacesAndNewlines),
            ])
            banner = "Creating flyer…"
            if let url = await waitForFlyer(jobId: id) {
                shareURL = url
                banner = "Flyer ready"
            } else {
                banner = "Flyer queued. It will show up shortly."
            }
        } catch {
            banner = error.localizedDescription
            bannerIsError = true
        }
        saving = false
    }

    private func waitForFlyer(jobId: Int) async -> URL? {
        for i in 0..<30 {
            if i > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            guard let job = try? await PythonAnywhereClient.shared.aiJob(id: jobId) else { continue }
            let status = (job["status"] as? String ?? "").lowercased()
            if status == "failed" || status == "error" {
                banner = (job["error"] as? String) ?? "Flyer failed"
                bannerIsError = true
                return nil
            }
            if let share = job["share_id"] as? String, !share.isEmpty {
                return SitePublicLink.flyer(share)
            }
            if status == "completed" || status == "done" {
                return nil
            }
        }
        return nil
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
