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
                    if auth.isLoggedIn {
                        NavigationLink("Tournaments") { SiteTournamentsView() }
                    }
                    NavigationLink("Volleyball") { SiteVolleyballView() }
                    if auth.isLoggedIn {
                        NavigationLink("AI Recaps") { SiteRecapsView() }
                        NavigationLink("Flyers") { SiteFlyersView() }
                    }
                }
                if auth.isLoggedIn {
                    Section("Create") {
                        NavigationLink("AI Summary") { SiteAISummaryView() }
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
                        SitePlayerAvatar(name: p.name, size: 36)
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
    @State private var canonicalName: String
    @State private var name: String
    @State private var nickname: String
    @State private var email: String
    @State private var height: String
    @State private var dob: String
    @State private var traits: [String]
    @State private var newTrait = ""
    @State private var error: String?
    @State private var banner: String?
    @State private var saving = false
    @State private var traitsBusy = false
    @State private var picker: PhotosPickerItem?
    @State private var characterPicker: PhotosPickerItem?
    @State private var aiImageUrl: String?
    @State private var aiBusy = false
    @ObservedObject private var auth = SiteAuthManager.shared

    init(player: SitePlayer) {
        _canonicalName = State(initialValue: player.name)
        _name = State(initialValue: player.name)
        _nickname = State(initialValue: player.nickname ?? "")
        _email = State(initialValue: player.email ?? "")
        _height = State(initialValue: player.height ?? "")
        _dob = State(initialValue: player.dateOfBirth ?? "")
        _traits = State(initialValue: player.aiImageTraits ?? [])
        _aiImageUrl = State(initialValue: player.aiImageUrl)
    }

    init(name: String) {
        _canonicalName = State(initialValue: name)
        _name = State(initialValue: name)
        _nickname = State(initialValue: "")
        _email = State(initialValue: "")
        _height = State(initialValue: "")
        _dob = State(initialValue: "")
        _traits = State(initialValue: [])
        _aiImageUrl = State(initialValue: nil)
    }

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            if let banner { SiteAddBanner(text: banner, isError: false) }
            HStack {
                Spacer()
                SitePlayerAvatar(name: canonicalName, size: 96)
                Spacer()
            }
            .listRowBackground(Color.clear)

            if auth.isLoggedIn {
                PhotosPicker("Upload face photo", selection: $picker, matching: .images)
                Section {
                    if let url = SitePublicLink.absolute(aiImageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFit()
                            default:
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay { if aiBusy { ProgressView() } }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text(aiBusy ? "Working in the background…" : "No AI character yet")
                            .foregroundStyle(.secondary)
                    }
                    Button(aiImageUrl == nil ? "Create AI character" : "Remake AI character") {
                        Task { await generateAICharacter() }
                    }
                    .disabled(aiBusy)
                    PhotosPicker("Upload AI character", selection: $characterPicker, matching: .images)
                        .disabled(aiBusy)
                    Text("A full-body person with this face and every signature look, including props (a motorhome look means a motorhome in the picture). Recaps and flyers add the sport. Generate one, or upload your own picture. Takes about a minute to generate — you can leave after you tap Create. If they don’t have a character yet, group pictures use their face photo. Players with no photo, signature look, or character are left out of group pictures.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("AI character")
                }
                Section {
                    if traits.isEmpty {
                        Text("No signature-look phrases yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(traits.enumerated()), id: \.offset) { index, phrase in
                        HStack(alignment: .top) {
                            Text(phrase)
                            Spacer()
                            Button {
                                Task { await removeTrait(at: index) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(traitsBusy)
                            .accessibilityLabel("Delete phrase")
                        }
                    }
                    HStack {
                        TextField("e.g. always wears an oversized bucket hat", text: $newTrait)
                            .onSubmit { Task { await addTrait() } }
                        Button("Add") { Task { await addTrait() } }
                            .disabled(traitsBusy || newTrait.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Separate details for the AI to exaggerate in recaps and flyers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Signature look")
                }
                Section("Profile") {
                    TextField("Name", text: $name)
                    TextField("Nickname", text: $nickname)
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Height", text: $height)
                    TextField("Date of birth", text: $dob)
                    Button("Save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                if let url = SitePublicLink.absolute(aiImageUrl) {
                    Section("AI character") {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFit()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                if !traits.isEmpty {
                    Section("Signature look") {
                        ForEach(Array(traits.enumerated()), id: \.offset) { _, phrase in
                            Text(phrase)
                        }
                    }
                }
                profileRow("Name", canonicalName)
                profileRow("Nickname", nickname)
                profileRow("Email", email)
                profileRow("Height", height)
                profileRow("Date of birth", dob)
            }

            NavigationLink("Doubles stats") {
                SitePlayerDetailView(name: canonicalName, year: String(Calendar.current.component(.year, from: Date())), section: .doubles)
            }
        }
        .navigationTitle(canonicalName)
        .task { await refreshFromServer() }
        .refreshable { await refreshFromServer() }
        .onChange(of: picker) { _, item in
            Task {
                guard auth.isLoggedIn, let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                do {
                    try await PythonAnywhereClient.shared.uploadPlayerPhoto(name: canonicalName, imageData: data, filename: "photo.jpg")
                    banner = "Photo updated"
                } catch { self.error = error.localizedDescription }
            }
        }
        .onChange(of: characterPicker) { _, item in
            Task {
                guard auth.isLoggedIn, let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                aiBusy = true
                error = nil
                banner = nil
                do {
                    let url = try await PythonAnywhereClient.shared.uploadPlayerAIImage(
                        name: canonicalName, imageData: data, filename: "character.jpg"
                    )
                    aiImageUrl = url
                    banner = "AI character uploaded"
                } catch {
                    self.error = error.localizedDescription
                }
                aiBusy = false
            }
        }
    }

    @ViewBuilder
    private func profileRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
            LabeledContent(label, value: value)
        }
    }

    private func apply(_ player: SitePlayer) {
        canonicalName = player.name
        name = player.name
        nickname = player.nickname ?? ""
        email = player.email ?? ""
        height = player.height ?? ""
        dob = player.dateOfBirth ?? ""
        traits = player.aiImageTraits ?? []
        aiImageUrl = player.aiImageUrl
    }

    private func refreshFromServer() async {
        guard let player = try? await PythonAnywhereClient.shared.player(named: canonicalName) else { return }
        apply(player)
    }

    private func save() async {
        guard auth.isLoggedIn else { return }
        saving = true
        error = nil
        banner = nil
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != canonicalName {
                try await PythonAnywhereClient.shared.renamePlayer(oldName: canonicalName, newName: trimmed)
                canonicalName = trimmed
            }
            try await PythonAnywhereClient.shared.updatePlayerInfo([
                "player_name": canonicalName,
                "nickname": nickname,
                "email": email,
                "height": height,
                "birthday": dob,
            ])
            banner = "Profile saved"
        } catch { self.error = error.localizedDescription }
        saving = false
    }

    private func addTrait() async {
        let phrase = newTrait.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        await saveTraits(traits + [phrase])
        if error == nil { newTrait = "" }
    }

    private func removeTrait(at index: Int) async {
        guard traits.indices.contains(index) else { return }
        var next = traits
        next.remove(at: index)
        await saveTraits(next)
    }

    private func saveTraits(_ next: [String]) async {
        guard auth.isLoggedIn else { return }
        traitsBusy = true
        error = nil
        do {
            traits = try await PythonAnywhereClient.shared.savePlayerAIImageTraits(name: canonicalName, phrases: next)
        } catch {
            self.error = error.localizedDescription
        }
        traitsBusy = false
    }

    private func generateAICharacter() async {
        guard auth.isLoggedIn else { return }
        aiBusy = true
        error = nil
        banner = nil
        do {
            let result = try await PythonAnywhereClient.shared.generatePlayerAIImage(name: canonicalName)
            if let url = result.imageUrl, !url.isEmpty {
                aiImageUrl = url
                banner = "AI character saved"
            } else if let jobId = result.jobId {
                banner = "Working in the background. You can leave and check this player again in a minute."
                if let url = await waitForPlayerAIImage(jobId: jobId) {
                    aiImageUrl = url
                    banner = "AI character saved"
                } else if error == nil {
                    banner = "Still generating. Check this player again in a minute."
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        aiBusy = false
    }

    private func waitForPlayerAIImage(jobId: Int) async -> String? {
        for i in 0..<90 {
            if i > 0 { try? await Task.sleep(nanoseconds: 4_000_000_000) }
            guard let job = try? await PythonAnywhereClient.shared.aiJob(id: jobId) else { continue }
            let status = (job["status"] as? String ?? "").lowercased()
            if status == "failed" || status == "error" {
                error = (job["error"] as? String) ?? "AI character failed"
                return nil
            }
            if status == "completed" || status == "complete" {
                if let url = job["ai_image_url"] as? String, !url.isEmpty { return url }
                if let url = job["result_summary"] as? String,
                   url.contains("/static/") || url.hasPrefix("http") {
                    return url
                }
                return nil
            }
        }
        return nil
    }
}

struct SiteNetworkView: View {
    @State private var payload: NetworkPayload?
    @State private var year = String(Calendar.current.component(.year, from: Date()))
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            if let error {
                SiteAddBanner(text: error, isError: true)
                    .padding()
            }
            if let p = payload {
                Picker("Year", selection: $year) {
                    ForEach(p.allYears, id: \.self) { y in
                        Text(y == "All years" ? "All" : y).tag(y)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                TextField("Search players", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.top, 8)
                Text("Tap a player to see who they play with, and how often they win together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                if loading { ProgressView().padding() }
                List(filteredPlayers) { node in
                    NavigationLink {
                        SiteNetworkPersonView(name: node.id, year: year, payload: p)
                    } label: {
                        HStack {
                            Text(node.label ?? node.id)
                            Spacer()
                            Text("\(node.games ?? 0) games")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            } else {
                ScrollView {
                    if loading {
                        ProgressView().padding()
                    } else {
                        Text("Pull down to reload.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .refreshable { await load() }
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

    private var filteredPlayers: [NetworkNode] {
        let nodes = (payload?.network.nodes ?? []).sorted { ($0.games ?? 0) > ($1.games ?? 0) }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return nodes }
        return nodes.filter { ($0.label ?? $0.id).lowercased().contains(q) }
    }

    private func load() async {
        loading = true
        error = nil
        do { payload = try await PythonAnywhereClient.shared.network(year: year) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct SiteNetworkPersonView: View {
    var name: String
    var year: String
    var payload: NetworkPayload
    @State private var mode = NetworkMode.partners
    @State private var minGames = 1
    @ObservedObject private var auth = SiteAuthManager.shared

    private enum NetworkMode: String, CaseIterable, Identifiable {
        case partners, shared
        var id: String { rawValue }
        var title: String {
            switch self {
            case .partners: return "Partners"
            case .shared: return "Shared games"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(NetworkMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if let node {
                Text("\(node.games ?? 0) games in \(payload.displayYear)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            HStack {
                Text("Min games")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach([1, 3, 5, 10], id: \.self) { n in
                    Button {
                        minGames = n
                    } label: {
                        Text("\(n)")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 36)
                            .padding(.vertical, 6)
                            .background(minGames == n ? SiteAddAccent.orange : Color(.secondarySystemFill))
                            .foregroundStyle(minGames == n ? Color.black : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Text(mode == .partners
                 ? "Teammates, with win rate as a pair."
                 : "Anyone in the same game, partner or opponent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if connections.isEmpty {
                Text("No connections with at least \(minGames) game\(minGames == 1 ? "" : "s").")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(connections, id: \.other) { row in
                    NavigationLink {
                        SiteNetworkPersonView(name: row.other, year: year, payload: payload)
                    } label: {
                        connectionRow(row)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(name)
        .toolbar {
            if auth.isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit") {
                        SiteEditPlayerView(name: name)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Stats") {
                    SitePlayerDetailView(name: name, year: year, section: .doubles)
                }
            }
        }
    }

    private var node: NetworkNode? {
        payload.network.nodes.first { $0.id == name }
    }

    private var connections: [(other: String, edge: NetworkEdge)] {
        let edges = mode == .partners ? payload.network.partnerEdges : payload.network.gameEdges
        return edges.compactMap { edge -> (String, NetworkEdge)? in
            guard (edge.games ?? 0) >= minGames else { return nil }
            if edge.source == name { return (edge.target, edge) }
            if edge.target == name { return (edge.source, edge) }
            return nil
        }
        .sorted { ($0.edge.games ?? 0) > ($1.edge.games ?? 0) }
    }

    @ViewBuilder
    private func connectionRow(_ row: (other: String, edge: NetworkEdge)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.other)
                .font(.body.weight(.semibold))
            HStack {
                Text("\(row.edge.games ?? 0) games")
                    .foregroundStyle(.secondary)
                if mode == .partners {
                    Spacer()
                    if let w = row.edge.wins, let l = row.edge.losses {
                        Text("\(w)–\(l)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(winPct(row.edge.winRate))
                        .monospacedDigit()
                        .foregroundStyle(winRateColor(row.edge.winRate))
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private func winPct(_ rate: Double?) -> String {
        let r = rate ?? 0
        let pct = r <= 1 ? r * 100 : r
        return String(format: "%.0f%%", pct)
    }

    private func winRateColor(_ rate: Double?) -> Color {
        let r = rate ?? 0
        let pct = r <= 1 ? r : r / 100
        if pct >= 0.55 { return .green }
        if pct >= 0.45 { return Color.yellow }
        return .red
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
        .refreshable { await load() }
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
            } else {
                Text("Pull down to reload.")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Volleyball")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SiteCopyLinkButton(url: SitePublicLink.volleyball(year: year))
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        payload = try? await PythonAnywhereClient.shared.volleyballStats(year: year)
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
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showRoster = false

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
            .refreshable { await reloadGames() }

            SiteAddActionButton(
                title: "Continue",
                filled: true,
                disabled: selected.isEmpty
            ) {
                showRoster = true
            }
            .padding(.horizontal)
            .padding(.top)
            Text("Next: review player photos, signature looks, and AI characters.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .navigationTitle("AI Summary")
        .navigationDestination(isPresented: $showRoster) {
            SiteAIRosterView(kind: .recap(gameType: gameType, gameIds: Array(selected)))
        }
        .task(id: gameType) {
            query = ""
            await loadRecent(resetSelection: true)
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

    private func reloadGames() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            await loadRecent(resetSelection: false)
        } else {
            await runSearch(q)
        }
    }

    private func loadRecent(resetSelection: Bool = true) async {
        loading = true
        if resetSelection {
            banner = nil
            selected = []
        }
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
            if resetSelection {
                selectLatestDay()
            } else {
                let ids = Set(games.map(\.id))
                selected = selected.intersection(ids)
            }
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

struct SiteFlyerDraft: Hashable {
    var players: [String]
    var gameType: String
    var gameName: String
    var eventDate: String
    var eventTime: String
    var location: String
    var imageDetails: String
}

struct SiteAIRosterView: View {
    enum Kind: Hashable {
        case recap(gameType: String, gameIds: [String])
        case flyer(SiteFlyerDraft)
    }

    var kind: Kind
    @State private var players: [SitePlayer] = []
    @State private var error: String?
    @State private var loading = false
    @State private var showStyle = false
    @State private var editingName: String?
    @State private var creating = false
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var shareURL: URL?
    @State private var flyerImageURL: URL?
    @State private var flyerDownloadURL: URL?

    var body: some View {
        List {
            Section {
                Text(rosterSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Review player pictures & signature looks")
                    .font(.headline)
            }
            if let banner {
                SiteAddBanner(text: banner, isError: bannerIsError)
            }
            if case .flyer = kind {
                if let flyerImageURL {
                    Text("Save the picture to Photos, then share it from there. Don’t send a link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AsyncImage(url: flyerImageURL) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFit()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let flyerDownloadURL {
                    SiteSaveFlyerPictureButton(imageURL: flyerDownloadURL)
                }
            } else if let shareURL {
                HStack {
                    ShareLink(item: shareURL)
                    SiteCopyLinkButton(url: shareURL)
                    Link("Open", destination: shareURL)
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if loading && players.isEmpty {
                ProgressView()
            }
            if players.isEmpty, error == nil, !loading {
                Text(emptyRosterText)
                    .foregroundStyle(.secondary)
            }
            ForEach(players) { player in
                Button {
                    editingName = player.name
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        SitePlayerAvatar(name: player.name, size: 52)
                        if let url = SitePublicLink.absolute(player.aiImageUrl) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                }
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.name).font(.headline)
                            Text("Edit photo & look")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: player.isReadyForIllustration ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                Text(readyText(for: player))
                            }
                            .font(.caption)
                            .foregroundStyle(player.isReadyForIllustration ? .green : .orange)
                            if let traits = player.aiImageTraits, !traits.isEmpty {
                                Text(traits.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else {
                                Text("No signature look yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Player looks")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text(rosterHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                switch kind {
                case .recap:
                    SiteAddActionButton(title: "Continue to style", filled: true) {
                        showStyle = true
                    }
                case .flyer:
                    SiteAddActionButton(
                        title: creating ? "Creating flyer…" : "Create flyer",
                        filled: true,
                        disabled: creating || players.isEmpty
                    ) {
                        Task { await createFlyer() }
                    }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationDestination(item: $editingName) { name in
            SiteEditPlayerView(name: name)
        }
        .navigationDestination(isPresented: $showStyle) {
            if case let .recap(gameType, gameIds) = kind {
                SiteAIStyleView(gameType: gameType, gameIds: gameIds)
            }
        }
        .refreshable { await load() }
        .onAppear { Task { await load() } }
        .onChange(of: editingName) { _, name in
            if name == nil { Task { await load() } }
        }
    }

    private var rosterSummary: String {
        switch kind {
        case let .recap(_, gameIds):
            let games = gameIds.count
            let people = players.count
            return "\(games) game\(games == 1 ? "" : "s") selected · \(people) player\(people == 1 ? "" : "s")"
        case .flyer:
            let people = players.count
            return "\(people) player\(people == 1 ? "" : "s") selected"
        }
    }

    private var rosterHint: String {
        switch kind {
        case .recap:
            return "Tap a player to edit their face photo, signature look, and AI character. Players need a photo, signature look, or saved AI character to appear in the illustration. If someone has no AI character yet, the group picture uses their face photo. Players with none of those are left out."
        case .flyer:
            return "Tap a player to edit their face photo, signature look, and AI character. Flyers use a saved AI character when one exists; otherwise they need a face photo. When it’s ready, save the picture to Photos."
        }
    }

    private var emptyRosterText: String {
        switch kind {
        case .recap: return "No players found for the selected games."
        case .flyer: return "No players selected."
        }
    }

    private func readyText(for player: SitePlayer) -> String {
        switch kind {
        case .recap:
            return player.isReadyForIllustration ? "Ready for illustration" : "Needs photo or signature look"
        case .flyer:
            return player.isReadyForIllustration ? "Ready for flyer" : "Needs face photo or AI character"
        }
    }

    private func load() async {
        loading = true
        do {
            switch kind {
            case let .recap(gameType, gameIds):
                players = try await PythonAnywhereClient.shared.aiRoster(gameType: gameType, gameIds: gameIds)
            case let .flyer(draft):
                players = try await PythonAnywhereClient.shared.aiRoster(players: draft.players)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func createFlyer() async {
        guard case let .flyer(draft) = kind else { return }
        creating = true
        banner = nil
        shareURL = nil
        flyerImageURL = nil
        flyerDownloadURL = nil
        bannerIsError = false
        do {
            let id = try await PythonAnywhereClient.shared.createFlyer([
                "players": draft.players,
                "game_type": draft.gameType,
                "game_name": draft.gameName,
                "event_date": draft.eventDate,
                "event_time": draft.eventTime,
                "location": draft.location,
                "image_details": draft.imageDetails,
            ])
            banner = "Working in the background. You can leave and check Flyers in about 5 minutes."
            let result = await siteWaitForAIShare(jobId: id, recap: false)
            if result.imageURL != nil || result.downloadURL != nil || result.pageURL != nil {
                shareURL = result.pageURL
                flyerImageURL = result.imageURL
                flyerDownloadURL = result.downloadURL ?? result.imageURL
                banner = "Flyer ready. Save it to Photos, then share that picture — don’t send a link."
            } else if let err = result.error {
                banner = err
                bannerIsError = true
            } else {
                banner = "Still working in the background. Check Flyers in a few minutes."
            }
        } catch {
            banner = error.localizedDescription
            bannerIsError = true
        }
        creating = false
    }
}

struct SiteAIStyleView: View {
    var gameType: String
    var gameIds: [String]
    @State private var promptStyle = "default"
    @State private var customPrompt = ""
    @State private var imageDetails = ""
    @State private var generating = false
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                Text("Writing style")
                    .font(.headline)
                styleCard(
                    id: "default",
                    title: "Standard Recap",
                    subtitle: "Clear summary from the game data",
                    detail: "Writes a factual recap from the scores, stats, and comments — no invented persona or gimmick voice."
                )
                styleCard(
                    id: "custom",
                    title: "Custom Prompt",
                    subtitle: "Write your own style",
                    detail: "Describe the tone, style, and personality you want."
                )
                if promptStyle == "custom" {
                    ZStack(alignment: .topLeading) {
                        if customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Example: Keep it short and punchy, focus on upsets and funny comments…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        TextEditor(text: $customPrompt)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: 100)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                }

                Text("Illustration")
                    .font(.headline)
                    .padding(.top, 8)
                Text("Include one AI-generated group illustration, or publish text only. Uses each player's saved AI character when they have one; otherwise face photos and/or signature looks. Players with none of those are left out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Extra illustration details (optional)")
                    .font(.subheadline.weight(.semibold))
                ZStack(alignment: .topLeading) {
                    if imageDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Example: sunset beach background, everyone celebrating at the net…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    TextEditor(text: $imageDetails)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 80)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                Text("Only used when you choose With illustration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    SiteAddActionButton(
                        title: generating ? "Writing…" : "Text only",
                        filled: false,
                        disabled: generating || !canGenerate
                    ) {
                        Task { await generate(imageMode: "none") }
                    }
                    SiteAddActionButton(
                        title: generating ? "Creating recap…" : "With illustration",
                        filled: true,
                        disabled: generating || !canGenerate
                    ) {
                        Task { await generate(imageMode: "image") }
                    }
                }
                Text("Illustration can take about 5 minutes — you can leave after you tap generate and check Recaps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .padding(.bottom, 24)
        }
        .navigationTitle("AI style")
        .scrollDismissesKeyboard(.interactively)
    }

    private var canGenerate: Bool {
        if promptStyle == "custom" {
            return !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func styleCard(id: String, title: String, subtitle: String, detail: String) -> some View {
        let selected = promptStyle == id
        return Button {
            promptStyle = id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? SiteAddAccent.orange : .secondary)
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? SiteAddAccent.orange.opacity(0.15) : Color(.secondarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? SiteAddAccent.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func generate(imageMode: String) async {
        generating = true
        banner = nil
        shareURL = nil
        bannerIsError = false
        do {
            let jobId = try await PythonAnywhereClient.shared.generateAISummary(
                gameType: gameType,
                gameIds: gameIds,
                promptStyle: promptStyle,
                customPrompt: promptStyle == "custom" ? customPrompt : "",
                imageMode: imageMode,
                imageDetails: imageDetails
            )
            banner = imageMode == "image"
                ? "Working in the background. You can leave and check Recaps in about 5 minutes."
                : "Working in the background. You can leave and check Recaps."
            let result = await siteWaitForAIShare(jobId: jobId, recap: true)
            if let url = result.pageURL {
                shareURL = url
                banner = "Recap ready"
            } else if let err = result.error {
                banner = err
                bannerIsError = true
            } else {
                banner = "Still working in the background. Check Recaps in a few minutes."
            }
        } catch {
            banner = error.localizedDescription
            bannerIsError = true
        }
        generating = false
    }
}

private struct SiteAIShareResult {
    var pageURL: URL?
    var imageURL: URL?
    var downloadURL: URL?
    var error: String?
}

private func siteWaitForAIShare(jobId: Int, recap: Bool) async -> SiteAIShareResult {
    for i in 0..<90 {
        if i > 0 { try? await Task.sleep(nanoseconds: 4_000_000_000) }
        guard let job = try? await PythonAnywhereClient.shared.aiJob(id: jobId) else { continue }
        let status = (job["status"] as? String ?? "").lowercased()
        if status == "failed" || status == "error" {
            return SiteAIShareResult(error: (job["error"] as? String) ?? (recap ? "Recap failed" : "Flyer failed"))
        }
        if let share = job["share_id"] as? String, !share.isEmpty {
            if recap {
                return SiteAIShareResult(pageURL: SitePublicLink.recap(share))
            }
            return SiteAIShareResult(
                pageURL: SitePublicLink.flyer(share),
                imageURL: SitePublicLink.absolute(job["flyer_image_url"] as? String),
                downloadURL: SitePublicLink.absolute(job["download_url"] as? String)
                    ?? SitePublicLink.flyerDownload(share)
            )
        }
        if status == "completed" || status == "done" {
            return SiteAIShareResult()
        }
    }
    return SiteAIShareResult()
}

struct SiteRecapsView: View {
    @State private var items: [RecapItem] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if items.isEmpty, error == nil {
                Text("No recaps yet. Pull down to refresh.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { r in
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.title).font(.headline)
                    HStack(spacing: 6) {
                        if let user = r.username, !user.isEmpty {
                            Text(user)
                        }
                        if let created = r.createdAt, !created.isEmpty {
                            Text(AdminTime.relative(created))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .navigationTitle(SiteAuthManager.shared.isAdmin ? "All recaps" : "AI Recaps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SiteAISummaryView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create recap")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            items = try await PythonAnywhereClient.shared.recaps()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SiteFlyersView: View {
    @State private var items: [FlyerItem] = []
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("Save the picture to Photos, then share it from there. Don’t send a link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if items.isEmpty, error == nil {
                Text("No flyers yet. Pull down to refresh, or create one from Create Flyer.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { flyer in
                VStack(alignment: .leading, spacing: 8) {
                    Text(flyer.title ?? "Flyer").font(.headline)
                    if let user = flyer.username, !user.isEmpty {
                        Text(user)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    flyerMeta(flyer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let img = flyer.flyerImageUrl, let u = SitePublicLink.absolute(img) {
                        AsyncImage(url: u) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let download = downloadURL(for: flyer) {
                        SiteSaveFlyerPictureButton(imageURL: download)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteFlyers)
        }
        .navigationTitle(SiteAuthManager.shared.isAdmin ? "All flyers" : "Flyers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SiteFlyerView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create flyer")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func flyerMeta(_ flyer: FlyerItem) -> Text {
        var parts: [String] = []
        if let players = flyer.players, !players.isEmpty {
            parts.append(players.joined(separator: ", "))
        }
        let when = [flyer.eventDate, flyer.eventTime].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !when.isEmpty { parts.append(when) }
        if let location = flyer.location, !location.isEmpty { parts.append(location) }
        return Text(parts.joined(separator: " · "))
    }

    private func downloadURL(for flyer: FlyerItem) -> URL? {
        if let raw = flyer.downloadUrl, let url = SitePublicLink.absolute(raw) { return url }
        if let id = flyer.shareId { return SitePublicLink.flyerDownload(id) }
        return SitePublicLink.absolute(flyer.flyerImageUrl)
    }

    private func load() async {
        do {
            items = try await PythonAnywhereClient.shared.flyers()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteFlyers(at offsets: IndexSet) {
        Task {
            for index in offsets {
                guard let id = items[index].shareId, !id.isEmpty else { continue }
                do {
                    try await PythonAnywhereClient.shared.deleteFlyer(shareId: id)
                } catch {
                    await MainActor.run { self.error = error.localizedDescription }
                }
            }
            await load()
        }
    }
}

struct SiteFlyerView: View {
    enum Field: Hashable { case player, location, details }

    @State private var gameType = "doubles"
    @State private var gameName = ""
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
    @State private var showRoster = false
    @FocusState private var focused: Field?

    private let timePresets = [16, 17, 18, 19, 20]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let banner {
                    SiteAddBanner(text: banner, isError: bannerIsError)
                }

                Picker("Game", selection: $gameType) {
                    Text("Doubles").tag("doubles")
                    Text("Vollis").tag("vollis")
                    Text("Other").tag("other")
                }
                .pickerStyle(.segmented)

                if gameType == "other" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Game name")
                            .font(.subheadline.weight(.semibold))
                        TextField("e.g. Spikeball night", text: $gameName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

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
                    DatePicker("Time", selection: $eventTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(timePresets, id: \.self) { hour in
                                let selectedPreset = isPresetSelected(hour)
                                Button { setTime(hour: hour) } label: {
                                    Text(timeLabel(hour))
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selectedPreset ? SiteAddAccent.orange : Color(.secondarySystemFill))
                                        .foregroundStyle(selectedPreset ? Color.black : Color.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
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
                    Text("The flyer is a picture you save to Photos and share from there. Don’t send a website link.")
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
                    title: "Continue",
                    filled: true,
                    disabled: selected.isEmpty
                        || location.trimmingCharacters(in: .whitespaces).isEmpty
                        || (gameType == "other" && gameName.trimmingCharacters(in: .whitespaces).isEmpty)
                ) {
                    showRoster = true
                }
                Text("Next: review player photos, signature looks, and AI characters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Flyer")
        .navigationDestination(isPresented: $showRoster) {
            SiteAIRosterView(kind: .flyer(flyerDraft))
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task { await loadPlayers() }
        .refreshable { await loadPlayers() }
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

    private func isPresetSelected(_ hour: Int) -> Bool {
        let cal = Calendar.current
        return cal.component(.hour, from: eventTime) == hour
            && cal.component(.minute, from: eventTime) == 0
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

    private var flyerDraft: SiteFlyerDraft {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "h:mm a"
        return SiteFlyerDraft(
            players: selected,
            gameType: gameType,
            gameName: gameType == "other" ? gameName.trimmingCharacters(in: .whitespaces) : "",
            eventDate: dateFmt.string(from: eventDate),
            eventTime: timeFmt.string(from: eventTime),
            location: location.trimmingCharacters(in: .whitespaces),
            imageDetails: imageDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
