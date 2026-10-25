import SwiftUI

struct SiteSeasonsView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var payload: SiteSeasonsPayload?
    @State private var error: String?
    @State private var loading = false
    @State private var creating = false
    @State private var created: SiteSeasonPayload?
    @State private var showCreated = false
    @State private var loadedAccount: String?
    @State private var loads = SiteSeasonLoadGate()

    private var visiblePayload: SiteSeasonsPayload? { loadedAccount == auth.token ? payload : nil }

    var body: some View {
        List {
            if loading && visiblePayload == nil { ProgressView("Loading seasons…") }
            if let error { Text(error).foregroundStyle(.red); Button("Try again") { Task { await load() } } }
            SiteListSection("Seasons") {
                Button { created = nil; creating = true } label: { Label("Create season", systemImage: "calendar.badge.plus") }
                SiteLimitedRows(visiblePayload?.seasons ?? []) { season in
                    NavigationLink { SiteSeasonDetailView(id: season.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(season.name).font(.headline)
                            Text(season.dates).font(.subheadline)
                            Text("\(season.status) · \(season.minimumDescription)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if visiblePayload?.seasons.isEmpty == true {
                    Text("Choose a name and dates to bring a league, tournament, or stretch of games together.").foregroundStyle(.secondary)
                }
            } footer: { Text("Seasons use only games you entered, and sync with the website.") }
            if let payload = visiblePayload, !payload.seasons.isEmpty {
                SiteListSection("All-time champions board") {
                    SiteLimitedRows(payload.champions) { winner in
                        NavigationLink { SiteSeasonPlayerView(seasonID: winner.seasonId, groupID: winner.groupId, name: winner.name) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(winner.name).font(.headline)
                                Text("\(winner.seasonName) · \(winner.groupTitle)")
                                Text("\(winner.startDate) – \(winner.endDate)").font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%.0f%% wins", winner.winPct * 100) + (winner.rating.map { " · Rating " + String(format: "%.2f", $0) } ?? ""))
                                    .font(.subheadline).monospacedDigit()
                            }.padding(.vertical, 4)
                        }
                    }
                    if payload.champions.isEmpty {
                        Text("Champions appear here after a season ends and players qualify.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Seasons")
        .task(id: auth.token) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating, onDismiss: {
            if created != nil { showCreated = true }
            Task { await load() }
        }) {
            NavigationStack { SiteSeasonEditorView { created = $0 } }
        }
        .navigationDestination(isPresented: $showCreated) {
            if loadedAccount == auth.token, let created { SiteSeasonDetailView(id: created.season.id, initialPayload: created) }
        }
    }

    private func load() async {
        let token = auth.token
        if loadedAccount != token { payload = nil; created = nil; showCreated = false; loadedAccount = token }
        let ticket = loads.begin(account: token)
        loading = true; error = nil
        defer { if loads.accepts(ticket, account: auth.token) { loading = false } }
        do {
            let result = try await PythonAnywhereClient.shared.seasons()
            guard loads.accepts(ticket, account: auth.token), !Task.isCancelled else { return }
            payload = result
        } catch {
            if loads.accepts(ticket, account: auth.token), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

struct SiteCreateSeasonView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var created: SiteSeasonPayload?
    @State private var createdAccount: String?
    var body: some View {
        if createdAccount == auth.token, let created { SiteSeasonDetailView(id: created.season.id, initialPayload: created) }
        else { SiteSeasonEditorView(dismissAfterSave: false) { created = $0; createdAccount = auth.token } }
    }
}

struct SiteSeasonEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = SiteAuthManager.shared
    var season: SiteSeason? = nil
    var dismissAfterSave = true
    var onSave: (SiteSeasonPayload) -> Void
    @State private var draft: SiteSeasonDraft
    @State private var saving = false
    @State private var error: String?
    @FocusState private var field: Field?
    private enum Field { case name, minimum }

    init(season: SiteSeason? = nil, dismissAfterSave: Bool = true, onSave: @escaping (SiteSeasonPayload) -> Void) {
        self.season = season
        self.dismissAfterSave = dismissAfterSave
        self.onSave = onSave
        _draft = State(initialValue: SiteSeasonDraft(season: season))
    }

    var body: some View {
        Form {
            SiteListSection("Season details") {
                TextField("Season name", text: $draft.name)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .accessibilityLabel("Season name").focused($field, equals: .name).submitLabel(.done)
                    .onSubmit { field = nil }
                DatePicker("Start day", selection: $draft.startDate, displayedComponents: .date)
                DatePicker("End day", selection: $draft.endDate, in: Calendar.current.startOfDay(for: draft.startDate)..., displayedComponents: .date)
            } footer: { Text("Both days are included. Each game format has separate standings using only your entries.") }
            SiteListSection("Minimum games per player") {
                Toggle("Automatic · same as the site", isOn: $draft.automatic)
                if !draft.automatic {
                    HStack {
                        Text("Games")
                        TextField("1", text: $draft.minimum).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).accessibilityLabel("Fixed minimum games")
                            .focused($field, equals: .minimum)
                    }
                }
                Text("Automatic divides each game format’s total games by 30, rounds down, and uses at least 1. It adapts to how busy your season is.")
                    .font(.subheadline).foregroundStyle(.secondary)
                DisclosureGroup("Why use automatic?") {
                    Text(SiteSeasonDraft.minimumExplanation).font(.subheadline).foregroundStyle(.secondary)
                }
            } footer: { Text("Players below the minimum stay visible with their progress.") }
            Section {
                if let error { Text(error).foregroundStyle(.red) }
                if let validation = draft.validationError, !draft.name.isEmpty { Text(validation).foregroundStyle(.secondary) }
                Button { Task { await save() } } label: {
                    if saving { ProgressView("Saving season…") }
                    else { Text(season == nil ? "Create season" : "Save changes") }
                }.disabled(saving || draft.validationError != nil)
            } footer: { Text("Seasons are private until you share them. They sync between the website and app.") }
        }
        .disabled(saving)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(season == nil ? "Create season" : "Edit season")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.startDate) { _, start in if SiteSeasonDraft.day(draft.endDate) < SiteSeasonDraft.day(start) { draft.endDate = start } }
        .onChange(of: draft.automatic) { _, automatic in if automatic && field == .minimum { field = nil } }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { field = nil } }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() async {
        guard draft.validationError == nil, !saving else { return }
        field = nil
        let token = auth.token
        saving = true; error = nil
        defer { saving = false }
        do {
            let result = try await PythonAnywhereClient.shared.saveSeason(draft, id: season?.id)
            guard token == auth.token else { return }
            onSave(result)
            if dismissAfterSave { dismiss() }
        } catch { if token == auth.token { self.error = error.localizedDescription } }
    }
}

struct SiteSeasonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.siteAppearance) private var appearance
    @ObservedObject private var auth = SiteAuthManager.shared
    var id: String
    @State private var payload: SiteSeasonPayload?
    @State private var selectedGroupID = ""
    @State private var loading = false
    @State private var working = false
    @State private var error: String?
    @State private var editing = false
    @State private var deleting = false
    @State private var loadedAccount: String?
    @State private var loads = SiteSeasonLoadGate()

    init(id: String, initialPayload: SiteSeasonPayload? = nil) {
        self.id = id
        _payload = State(initialValue: initialPayload)
        _loadedAccount = State(initialValue: SiteAuthManager.shared.token)
        _selectedGroupID = State(initialValue: initialPayload?.groups.first?.id ?? "")
    }

    private var selectedGroup: SiteSeasonGroup? {
        guard loadedAccount == auth.token else { return nil }
        return payload?.groups.first(where: { $0.id == selectedGroupID }) ?? payload?.groups.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if loading && payload == nil { ProgressView("Loading season…").padding() }
                if let error { Text(error).foregroundStyle(.red).padding(); Button("Try again") { Task { await load() } }.padding(.horizontal) }
                if loadedAccount == auth.token, let payload {
                    summary(payload)
                    if let group = selectedGroup {
                        awards(group, season: payload.season)
                        standings(group.stats, group: group, title: "Standings").id(group.id + "-standings")
                        if !group.rareStats.isEmpty {
                            standings(group.rareStats, group: group, title: "Working toward qualification").id(group.id + "-qualifying")
                        }
                    }
                    if payload.groups.isEmpty {
                        SiteContentCard(title: "No season games yet") {
                            Text("Games you enter between \(payload.season.startDate) and \(payload.season.endDate) will appear here automatically.")
                        }.padding(.horizontal, 12)
                    }
                    DisclosureGroup("How this season works") {
                        Text(payload.minimumExplanation).padding(.vertical, 8)
                        Text(payload.awardsExplanation)
                    }.font(.subheadline).padding().modifier(SiteCardSurface()).padding(.horizontal, 12)
                }
            }.padding(.vertical, 12)
        }
        .background(appearance.background)
        .navigationTitle(loadedAccount == auth.token ? (payload?.season.name ?? "Season") : "Season")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: auth.token) { await load() }
        .refreshable { await load() }
        .toolbar {
            if loadedAccount == auth.token, payload != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit season", systemImage: "pencil") { editing = true }
                        Button("Delete season", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Season options").disabled(working)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let payload {
                NavigationStack {
                    SiteSeasonEditorView(season: payload.season) { result in
                        loads.invalidate(); loading = false
                        self.payload = result
                        keepSelection(in: result)
                    }
                }
            }
        }
        .confirmationDialog("Delete this season?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete season", role: .destructive) { Task { await delete() } }
        } message: { Text("This removes the season and disables its shared link. Your game records stay saved.") }
    }

    private func summary(_ payload: SiteSeasonPayload) -> some View {
        SiteContentCard(title: payload.season.status) {
            Text(payload.season.dates).font(.headline)
            Text("\(payload.gameCount) games · \(payload.season.minimumDescription)").font(.subheadline).foregroundStyle(.secondary)
            if payload.groups.count > 1 {
                Picker("Game", selection: $selectedGroupID) {
                    ForEach(payload.groups) { group in Text(group.title).tag(group.id) }
                }.pickerStyle(.menu)
            }
            DisclosureGroup("Share season") {
                VStack(alignment: .leading, spacing: 12) {
                    if let url = shareURL(payload.season) {
                        Text("Anyone with this link can view this season and its player stats.").font(.caption).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 20) { shareActions(url) }
                            VStack(alignment: .leading, spacing: 12) { shareActions(url) }
                        }
                        Button("Stop sharing") { Task { await share(false) } }
                    } else {
                        Text("Create a read-only link to share this private season.").font(.caption).foregroundStyle(.secondary)
                        Button("Create share link") { Task { await share(true) } }
                    }
                    if working { ProgressView() }
                }.padding(.top, 8).disabled(working)
            }
        }.padding(.horizontal, 12)
    }

    @ViewBuilder private func shareActions(_ url: URL) -> some View {
        ShareLink(item: url)
        SiteCopyLinkButton(url: url, showsTitle: true, isPublicLink: true)
    }

    private func shareURL(_ season: SiteSeason) -> URL? {
        guard let url = SitePublicLink.absolute(season.shareUrl) else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let group = selectedGroup { parts?.queryItems = [URLQueryItem(name: "group", value: group.id)] }
        return parts?.url
    }

    private func awards(_ group: SiteSeasonGroup, season: SiteSeason) -> some View {
        SiteContentCard(title: group.title) {
            Text("\(group.gameCount) games · \(group.minimumGames) games per player to qualify").font(.subheadline).foregroundStyle(.secondary)
            Text(season.status == "Completed" ? "Season champion" : "Championship leader").font(.headline)
            ForEach(group.champions) { player in
                NavigationLink {
                    SiteSeasonPlayerView(seasonID: id, groupID: group.id, name: player.name)
                } label: {
                    Text("\(player.name) · " + (group.awardMetric == "rating" ? "\(player.ratingText) rating" : "\(player.winPercent) wins"))
                }
            }
            if group.champions.isEmpty { Text("No qualifying players yet.").foregroundStyle(.secondary) }
            Divider()
            Text(season.status == "Completed" ? "Most improved" : "Most improved so far").font(.headline)
            ForEach(group.mostImproved) { player in
                NavigationLink {
                    SiteSeasonPlayerView(seasonID: id, groupID: group.id, name: player.name)
                } label: { Text("\(player.name) · " + String(format: "%+.2f", player.ratingGain ?? 0)) }
            }
            if group.mostImproved.isEmpty {
                Text(group.ratingEnabled ? "No qualifying rating gain yet." : "No skill ratings for this format.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if group.ratingEnabled && group.unratedGames > 0 {
                Text("\(group.ratedGames) rated · \(group.unratedGames) excluded from ratings").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 12)
    }

    private func standings(_ players: [SiteSeasonPlayer], group: SiteSeasonGroup, title: String) -> some View {
        RankingTable(title: title, rows: players.map(\.rankingRow), showRating: group.ratingEnabled,
                     year: "All years", section: .doubles,
                     playerDestination: { name in AnyView(SiteSeasonPlayerView(seasonID: id, groupID: group.id, name: name)) },
                     playerNotes: Dictionary(uniqueKeysWithValues: players.filter { !$0.qualified }.map {
                         ($0.name, "\($0.gamesNeeded) more game\($0.gamesNeeded == 1 ? "" : "s") to qualify")
                     }))
    }

    private func keepSelection(in result: SiteSeasonPayload) {
        if !result.groups.contains(where: { $0.id == selectedGroupID }) { selectedGroupID = result.groups.first?.id ?? "" }
    }

    private func load() async {
        let token = auth.token
        if loadedAccount != token {
            payload = nil; loadedAccount = token; working = false; loads.invalidate()
        }
        guard !working else { return }
        let ticket = loads.begin(account: token)
        loading = true; error = nil
        defer { if loads.accepts(ticket, account: auth.token) { loading = false } }
        do {
            let result = try await PythonAnywhereClient.shared.season(id: id)
            guard loads.accepts(ticket, account: auth.token), !Task.isCancelled else { return }
            payload = result
            keepSelection(in: result)
        } catch {
            if loads.accepts(ticket, account: auth.token), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func share(_ enabled: Bool) async {
        guard !working else { return }
        loads.invalidate(); loading = false
        let token = auth.token
        working = true; error = nil
        defer { working = false }
        do {
            let season = try await PythonAnywhereClient.shared.shareSeason(id: id, enabled: enabled)
            guard token == auth.token else { return }
            payload?.season = season
        } catch { if token == auth.token { self.error = error.localizedDescription } }
    }

    private func delete() async {
        guard !working else { return }
        loads.invalidate(); loading = false
        let token = auth.token
        working = true; error = nil
        defer { working = false }
        do {
            try await PythonAnywhereClient.shared.deleteSeason(id: id)
            guard token == auth.token else { return }
            dismiss()
        } catch { if token == auth.token { self.error = error.localizedDescription } }
    }
}

private extension SiteSeasonPlayer {
    var rankingRow: RankingRow {
        RankingRow(name: name, wins: wins, losses: losses, winPct: winPct, games: games, rating: rating, ties: ties)
    }
}

struct SiteSeasonPlayerView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    var seasonID: String
    var groupID: String
    var name: String
    @State private var payload: SiteSeasonPayload?
    @State private var error: String?
    @State private var loading = false
    @State private var loadedAccount: String?
    @State private var loads = SiteSeasonLoadGate()

    var body: some View {
        List {
            if loading && payload == nil { ProgressView("Loading player…") }
            if let error { Text(error).foregroundStyle(.red); Button("Try again") { Task { await load() } } }
            if loadedAccount == auth.token, let payload, let player = payload.player {
                SiteListSection(payload.season.name) {
                    Text(player.groupTitle).font(.headline)
                    Text(payload.season.dates)
                    Text("\(player.stats.wins) wins · \(player.stats.losses) losses" + (player.stats.ties > 0 ? " · \(player.stats.ties) ties" : ""))
                    Text("\(player.stats.winPercent) wins · \(player.stats.games) games" + (player.stats.rating != nil ? " · Rating \(player.stats.ratingText)" : ""))
                    if let gain = player.stats.ratingGain { Text("Change since first playing day: " + String(format: "%+.2f", gain)) }
                    Text(player.stats.qualified ? "Qualified" : "\(player.stats.gamesNeeded) more games to qualify").foregroundStyle(.secondary)
                }
                SiteListSection("Games in this season") {
                    SiteLimitedRows(player.games) { game in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(game.result) · \(game.day)").font(.headline)
                            Text(game.winners.joined(separator: " & ") + (game.winnerScore.map { " \($0)" } ?? ""))
                            Text("vs. " + game.losers.joined(separator: " & ") + (game.loserScore.map { " \($0)" } ?? ""))
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .task(id: auth.token) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let token = auth.token
        if loadedAccount != token { payload = nil; loadedAccount = token }
        let ticket = loads.begin(account: token)
        loading = true; error = nil
        defer { if loads.accepts(ticket, account: auth.token) { loading = false } }
        do {
            let result = try await PythonAnywhereClient.shared.season(id: seasonID, player: name, group: groupID)
            guard loads.accepts(ticket, account: auth.token), !Task.isCancelled else { return }
            payload = result
        } catch {
            if loads.accepts(ticket, account: auth.token), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
