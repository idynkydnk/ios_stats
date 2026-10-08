import SwiftUI

struct SiteAddDoublesView: View {
    var gameToEdit: DoublesGame?
    var header: AnyView? = nil
    var onDone: () -> Void

    enum Field: Hashable {
        case w1, w2, l1, l2, wScore, lScore, comment, location
    }

    @State private var winner1 = ""
    @State private var winner2 = ""
    @State private var loser1 = ""
    @State private var loser2 = ""
    @State private var winnerScore: Int?
    @State private var loserScore: Int?
    @State private var comments = ""
    @State private var location = siteLastGameLocation()
    @State private var players: [String] = []
    @State private var error: String?
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var saving = false
    @State private var successTick = 0
    @Environment(\.gameSaveStatus) private var gameSaveStatus
    @State private var rematch: (String, String, String, String)?
    @State private var today: TodaysDoublesDashboard?
    @FocusState private var focused: Field?
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = SiteOfflineQueue.shared
    @ObservedObject private var auth = SiteAuthManager.shared

    private let winnerChips = [21, 15, 22, 23, 16]

    var body: some View {
        SiteAddFormScrollView(focused: focused, header: header) {
            VStack(alignment: .leading, spacing: 14) {
                SiteContentCard(title: "Doubles game") {
                    if let error {
                        SiteAddBanner(text: error, isError: true)
                    }

                    playerRow("Winner 1", text: $winner1, field: .w1, next: .w2)
                    playerRow("Winner 2", text: $winner2, field: .w2, next: .l1)
                    playerRow("Loser 1", text: $loser1, field: .l1, next: .l2)
                    playerRow("Loser 2", text: $loser2, field: .l2, next: .wScore)

                    SiteAddScoreRow(label: "Winners' score", value: $winnerScore, field: .wScore, focus: $focused, submit: .next, onSubmit: { advance(to: .lScore) }, onFocus: {})
                    if focused == .wScore {
                        SiteAddScoreChips(scores: winnerChips, selected: winnerScore) { s in
                            winnerScore = s
                            if gameToEdit == nil { advance(to: .lScore) }
                        }
                    }

                    SiteAddScoreRow(label: "Losers' score", value: $loserScore, field: .lScore, focus: $focused, submit: .done, onSubmit: { focused = nil }, onFocus: {})
                    if focused == .lScore {
                        SiteAddScoreChips(scores: siteLoserScores(winner: winnerScore), selected: loserScore) { s in
                            loserScore = s
                            focused = nil
                        }
                    }

                    SiteAddCommentRow(text: $comments, field: .comment, focus: $focused)
                    SiteAddTextRow(label: "Location (optional)", text: $location, field: .location, focus: $focused, submit: .done, onSubmit: { focused = nil })

                    HStack(spacing: 8) {
                        SiteAddActionButton(title: saving ? "Saving…" : (gameToEdit == nil ? "Save" : "Update"), filled: true, disabled: saving) {
                            Task { await save() }
                        }
                        SiteAddActionButton(title: "Rematch", disabled: rematch == nil && today?.games.first == nil) {
                            applyRematch()
                        }
                    }
                    HStack(spacing: 8) {
                        SiteAddActionButton(title: "Swap W/L") { swapSides() }
                        SiteAddActionButton(title: "Clear") { clearForm(focusFirst: true) }
                    }

                }
                .disabled(saving)

                if let today, !today.stats.isEmpty || !today.games.isEmpty {
                    todayBoard(today)
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .sensoryFeedback(.success, trigger: successTick)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    focused = nil
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
        .task { await bootstrap() }
        .task(id: auth.statsViewRevision) {
            players = (try? await PythonAnywhereClient.shared.doublesPlayers()) ?? []
        }
        .onChange(of: gameToEdit?.id) { _, _ in applyEdit() }
        .onAppear {
            if gameToEdit == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .w1 }
            }
        }
    }

    @ViewBuilder
    private func playerRow(_ label: String, text: Binding<String>, field: Field, next: Field) -> some View {
        SiteAddTextRow(label: label, text: text, field: field, focus: $focused, submit: .done, onSubmit: {
            focused = nil
        })
        if focused == field {
            SiteAddSuggestionList(names: suggestions(for: text.wrappedValue, field: field)) { name in
                text.wrappedValue = name
                if gameToEdit == nil { advance(to: next) }
            }
        }
    }

    @ViewBuilder
    private func todayBoard(_ dash: TodaysDoublesDashboard) -> some View {
        VStack(spacing: 20) {
            RankingTable(title: "Today's Standings", rows: dash.stats, showRating: true,
                         showPlusMinus: true, sortLikeToday: true,
                         year: String(Calendar.current.component(.year, from: Date())), section: .doubles)
                .padding(.horizontal, -16)
            SiteExpandableSection(title: "Games", count: dash.games.count, subtitle: "Today") {
                if dash.games.isEmpty {
                    Text("No doubles played today yet.").foregroundStyle(.secondary).padding()
                } else {
                    ForEach(dash.games) { game in
                        DoublesGameRow(game: game, year: String(Calendar.current.component(.year, from: Date())), section: .doubles)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private func suggestions(for query: String, field: Field) -> [String] {
        let others: [String] = {
            switch field {
            case .w1: return [winner2, loser1, loser2]
            case .w2: return [winner1, loser1, loser2]
            case .l1: return [winner1, winner2, loser2]
            case .l2: return [winner1, winner2, loser1]
            default: return []
            }
        }()
        return siteFilterPlayers(players, query: query, excluding: others)
    }

    private func advance(to field: Field) {
        focused = field
    }

    private func bootstrap() async {
        applyEdit()
        await refreshToday()
        if rematch == nil, let g = today?.games.first {
            rematch = (g.winner1 ?? "", g.winner2 ?? "", g.loser1 ?? "", g.loser2 ?? "")
        }
    }

    private func refreshToday() async {
        today = try? await PythonAnywhereClient.shared.todaysDoublesDashboard()
    }

    private func applyEdit() {
        guard let g = gameToEdit else { return }
        winner1 = g.winner1 ?? ""; winner2 = g.winner2 ?? ""
        loser1 = g.loser1 ?? ""; loser2 = g.loser2 ?? ""
        winnerScore = g.winnerScore; loserScore = g.loserScore
        comments = g.comment
        location = g.location ?? siteLastGameLocation()
    }

    private func applyRematch() {
        let r = rematch ?? {
            guard let g = today?.games.first else { return nil }
            return (g.winner1 ?? "", g.winner2 ?? "", g.loser1 ?? "", g.loser2 ?? "")
        }()
        guard let r else { return }
        winner1 = r.0; winner2 = r.1; loser1 = r.2; loser2 = r.3
        winnerScore = nil; loserScore = nil; comments = ""
        focused = .wScore
    }

    private func swapSides() {
        swap(&winner1, &loser1)
        swap(&winner2, &loser2)
        swap(&winnerScore, &loserScore)
    }

    private func clearForm(focusFirst: Bool) {
        winner1 = ""; winner2 = ""; loser1 = ""; loser2 = ""
        winnerScore = nil; loserScore = nil; comments = ""
        location = siteLastGameLocation()
        error = nil
        if focusFirst { focused = .w1 }
    }

    private func save() async {
        guard !saving else { return }
        guard let ws = winnerScore, let ls = loserScore, ws > ls else {
            error = "Winner score must be greater than loser score."
            return
        }
        let names = [winner1, winner2, loser1, loser2].map { $0.trimmingCharacters(in: .whitespaces) }
        guard Set(names.map { $0.lowercased() }).count == 4, names.allSatisfy({ !$0.isEmpty }) else {
            error = "Four unique player names required."
            return
        }
        var savedGame: SiteSavedGameReceipt?
        saving = true
        banner = nil
        error = nil
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: Any] = [
            "winner1": names[0], "winner2": names[1],
            "loser1": names[2], "loser2": names[3],
            "winner_score": ws, "loser_score": ls,
            "comments": comments,
            "entered_timezone": TimeZone.current.identifier,
            "location": cleanLocation,
        ]
        // Edits omit the date so the server keeps the original game time,
        // including when an offline edit is synced later.
        if gameToEdit == nil { fields["game_date"] = siteNowString() }
        focused = nil
        if gameToEdit == nil {
            savedGame = SiteSavedGameReceipt(title: "Doubles", status: "Saving…", isSaving: true,
                winners: "\(names[0]) & \(names[1])", losers: "\(names[2]) & \(names[3])",
                winnerScore: ws, loserScore: ls, location: cleanLocation, comment: comments)
        }
        if let savedGame { gameSaveStatus(savedGame) }
        do {
            if !network.isConnected {
                if let g = gameToEdit {
                    queue.enqueue(method: "PUT", path: "/api/doubles/games/\(g.id)", body: fields)
                } else {
                    queue.enqueue(method: "POST", path: "/api/doubles/games", body: fields)
                }
                banner = "Saved offline — will sync"
            } else if let g = gameToEdit {
                _ = try await PythonAnywhereClient.shared.updateDoubles(id: g.id, fields: fields)
                banner = "Game saved"
            } else {
                try await PythonAnywhereClient.shared.createDoubles(fields)
                banner = "Game saved"
            }
        } catch {
            savedGame?.status = error.localizedDescription
            savedGame?.isSaving = false
            savedGame?.isError = true
            if let savedGame { gameSaveStatus(savedGame) }
            saving = false
            banner = nil
            self.error = error.localizedDescription
            return
        }
        siteRememberGameLocation(cleanLocation)
        saving = false
        rematch = (names[0], names[1], names[2], names[3])
        sitePromote(names, in: &players)
        savedGame?.status = banner ?? "Game saved"
        savedGame?.isSaving = false
        if let savedGame { gameSaveStatus(savedGame) }
        clearForm(focusFirst: false)
        focused = nil
        bannerIsError = false
        successTick += 1
        if gameToEdit != nil { onDone() }
        // Refresh failures must not undo the confirmed save or block the next entry.
        players = (try? await PythonAnywhereClient.shared.doublesPlayers()) ?? players
        await refreshToday()
    }
}

struct SiteAddVollisView: View {
    var gameToEdit: VollisGame?
    var header: AnyView? = nil
    var onDone: () -> Void

    enum Field: Hashable { case winner, loser, wScore, lScore, location }

    @State private var winner = ""
    @State private var loser = ""
    @State private var winnerScore: Int?
    @State private var loserScore: Int?
    @State private var location = siteLastGameLocation()
    @State private var players: [String] = []
    @State private var todayGames: [VollisGame] = []
    @State private var error: String?
    @State private var banner: String?
    @State private var saving = false
    @State private var successTick = 0
    @Environment(\.gameSaveStatus) private var gameSaveStatus
    @FocusState private var focused: Field?
    @ObservedObject private var auth = SiteAuthManager.shared

    private let winnerChips = Array(11...21)

    var body: some View {
        SiteAddFormScrollView(focused: focused, header: header) {
            VStack(alignment: .leading, spacing: 14) {
                SiteContentCard(title: "Vollis game") {
                    if let error { SiteAddBanner(text: error, isError: true) }

                    SiteAddTextRow(label: "Winner", text: $winner, field: .winner, focus: $focused, submit: .done, onSubmit: {
                        focused = nil
                    })
                    if focused == .winner {
                        SiteAddSuggestionList(names: siteFilterPlayers(players, query: winner, excluding: [loser])) { name in
                            winner = name
                            if gameToEdit == nil { focused = .loser }
                        }
                    }

                    SiteAddTextRow(label: "Loser", text: $loser, field: .loser, focus: $focused, submit: .done, onSubmit: {
                        focused = nil
                    })
                    if focused == .loser {
                        SiteAddSuggestionList(names: siteFilterPlayers(players, query: loser, excluding: [winner])) { name in
                            loser = name
                            if gameToEdit == nil { focused = .wScore }
                        }
                    }

                    SiteAddScoreRow(label: "Winner's score", value: $winnerScore, field: .wScore, focus: $focused, onSubmit: { focused = .lScore })
                    if focused == .wScore {
                        SiteAddScoreChips(scores: winnerChips, selected: winnerScore) { s in
                            winnerScore = s
                            if gameToEdit == nil { focused = .lScore }
                        }
                    }

                    SiteAddScoreRow(label: "Loser's score", value: $loserScore, field: .lScore, focus: $focused, submit: .next, onSubmit: { focused = .location })
                    if focused == .lScore {
                        SiteAddScoreChips(scores: siteLoserScores(winner: winnerScore ?? 11), selected: loserScore) { s in
                            loserScore = s
                            focused = nil
                        }
                    }

                    SiteAddTextRow(label: "Location (optional)", text: $location, field: .location, focus: $focused, submit: .done, onSubmit: { focused = nil })

                    HStack(spacing: 8) {
                        SiteAddActionButton(title: saving ? "Saving…" : (gameToEdit == nil ? "Save" : "Update"), filled: true, disabled: saving || !auth.isLoggedIn) {
                            Task { await save() }
                        }
                        SiteAddActionButton(title: "Clear") {
                            clearForm()
                        }
                    }

                }
                .disabled(saving)

                if !todayGames.isEmpty {
                    SiteExpandableSection(title: "Games", count: todayGames.count, subtitle: "Today") {
                        ForEach(todayGames) { g in
                            VollisGameRow(game: g)
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .sensoryFeedback(.success, trigger: successTick)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    focused = nil
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
        .task { await load() }
        .onChange(of: auth.statsViewRevision) { _, _ in
            Task { await refreshToday() }
        }
        .onAppear {
            if gameToEdit == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .winner }
            }
        }
    }

    private func load() async {
        if let g = gameToEdit {
            winner = g.winner ?? ""; loser = g.loser ?? ""
            winnerScore = g.winnerScore; loserScore = g.loserScore
            location = g.location ?? siteLastGameLocation()
        }
        await refreshToday()
    }

    private func refreshToday() async {
        players = (try? await PythonAnywhereClient.shared.vollisPlayers()) ?? []
        let year = String(Calendar.current.component(.year, from: Date()))
        let all = (try? await PythonAnywhereClient.shared.vollisGames(year: year, preview: false))?.games ?? []
        todayGames = all.filter { siteIsToday($0.date) }
    }

    private func clearForm() {
        winner = ""; loser = ""
        winnerScore = nil; loserScore = nil
        location = siteLastGameLocation()
        error = nil
        focused = .winner
    }

    private func save() async {
        guard !saving else { return }
        let w = winner.trimmingCharacters(in: .whitespaces)
        let l = loser.trimmingCharacters(in: .whitespaces)
        guard let ws = winnerScore, let ls = loserScore, ws > ls, w != l, !w.isEmpty, !l.isEmpty else {
            error = "Check names and scores."
            return
        }
        var savedGame: SiteSavedGameReceipt?
        saving = true
        banner = nil
        error = nil
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: Any] = [
            "winner": w, "loser": l,
            "winner_score": ws, "loser_score": ls,
            "entered_timezone": TimeZone.current.identifier,
            "location": cleanLocation,
        ]
        // Edits omit the date so the server keeps the original game time.
        if gameToEdit == nil { fields["game_date"] = siteNowString() }
        focused = nil
        if gameToEdit == nil {
            savedGame = SiteSavedGameReceipt(title: "Vollis", status: "Saving…", isSaving: true, winners: w, losers: l,
                winnerScore: ws, loserScore: ls, location: cleanLocation)
        }
        if let savedGame { gameSaveStatus(savedGame) }
        do {
            if let g = gameToEdit {
                try await PythonAnywhereClient.shared.updateVollis(id: g.id, fields: fields)
            } else {
                try await PythonAnywhereClient.shared.createVollis(fields)
            }
        } catch {
            savedGame?.status = error.localizedDescription
            savedGame?.isSaving = false
            savedGame?.isError = true
            if let savedGame { gameSaveStatus(savedGame) }
            saving = false
            self.error = error.localizedDescription
            return
        }
        siteRememberGameLocation(cleanLocation)
        saving = false
        banner = "Game saved"
        successTick += 1
        sitePromote([w, l], in: &players)
        savedGame?.status = "Game saved"
        savedGame?.isSaving = false
        if let savedGame { gameSaveStatus(savedGame) }
        clearForm()
        focused = nil
        if gameToEdit != nil { onDone() }
        await refreshToday()
    }
}

struct SiteAddOtherView: View {
    var header: AnyView? = nil

    enum Field: Hashable {
        case gameName, winner(Int), loser(Int), winnerIndiv(Int), loserIndiv(Int), teamW, teamL, comment, location
    }

    @State private var gameType = ""
    @State private var gameName = ""
    @State private var scoreType = "team"
    @State private var winners: [String] = [""]
    @State private var losers: [String] = [""]
    @State private var winnerIndiv: [Int?] = [nil]
    @State private var loserIndiv: [Int?] = [nil]
    @State private var teamWinnerScore: Int?
    @State private var teamLoserScore: Int?
    @State private var comment = ""
    @State private var location = siteLastGameLocation()
    @State private var knownNames: [String] = ["Vollis"]
    @State private var loadingGameNames = false
    @State private var gameNamesError: String?
    @State private var knownTypes: [String] = []
    @State private var entryDefaults: [String: PythonAnywhereClient.OtherGameEntryInfo] = [:]
    @State private var players: [String] = []
    @State private var winnerChips: [Int] = [21, 25, 15, 18, 20]
    @State private var loserChips: [Int] = [19, 23, 12, 16, 17]
    @State private var indivChips: [Int] = Array(0...10)
    @State private var error: String?
    @State private var banner: String?
    @State private var saving = false
    @State private var successTick = 0
    @Environment(\.gameSaveStatus) private var gameSaveStatus
    @State private var todayGames: [OtherGame] = []
    @State private var todayVollisGames: [VollisGame] = []
    @ObservedObject private var auth = SiteAuthManager.shared

    private var isVollis: Bool {
        gameName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Vollis") == .orderedSame
    }
    @FocusState private var focused: Field?

    var body: some View {
        SiteAddFormScrollView(focused: focused, header: header) {
            VStack(alignment: .leading, spacing: 14) {
                SiteContentCard(title: "Other game") {
                    if let error { SiteAddBanner(text: error, isError: true) }

                    HStack(spacing: 8) {
                        SiteAddTextRow(label: "Game name", text: $gameName, field: .gameName, focus: $focused, submit: .done, onSubmit: {
                            focused = nil
                            Task { await applyGameName(advanceFocus: false) }
                        })
                        Menu {
                            ForEach(knownNames, id: \.self) { name in
                                Button(name) {
                                    gameName = name
                                    Task { await applyGameName() }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Choose a previous game")
                        .accessibilityHint("Shows all previous game names")
                    }
                    if loadingGameNames {
                        ProgressView("Loading game names…")
                    } else if let gameNamesError {
                        Text(gameNamesError).font(.footnote).foregroundStyle(.secondary)
                        Button("Retry loading game names") {
                            Task { await loadGameNames() }
                        }
                    }

                    if !isVollis && !knownTypes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(knownTypes, id: \.self) { t in
                                    Button(t) { gameType = t }
                                        .buttonStyle(.bordered)
                                        .tint(gameType == t ? SiteAddAccent.orange : .secondary)
                                }
                            }
                        }
                    }

                    if !isVollis {
                        Picker("Scoring", selection: $scoreType) {
                            Text("Team").tag("team")
                            Text("Individual").tag("individual")
                            Text("None").tag("none")
                        }
                        .pickerStyle(.segmented)
                    }

                    Text("Winners").font(.headline)
                    ForEach(winners.indices, id: \.self) { i in
                        playerSlot(side: .winner, index: i)
                    }
                    if !isVollis {
                        Button("Add winner") { addSlot(winner: true) }
                            .font(.subheadline)
                    }

                    Text("Losers").font(.headline)
                    ForEach(losers.indices, id: \.self) { i in
                        playerSlot(side: .loser, index: i)
                    }
                    if !isVollis {
                        Button("Add loser") { addSlot(winner: false) }
                            .font(.subheadline)
                    }

                    if scoreType == "team" {
                        SiteAddScoreRow(label: "Winner score", value: $teamWinnerScore, field: .teamW, focus: $focused, onSubmit: { focused = .teamL })
                        if focused == .teamW {
                            SiteAddScoreChips(scores: winnerChips, selected: teamWinnerScore) { s in
                                teamWinnerScore = s
                                focused = .teamL
                            }
                        }
                        SiteAddScoreRow(label: "Loser score", value: $teamLoserScore, field: .teamL, focus: $focused, submit: .next, onSubmit: { focused = isVollis ? .location : .comment })
                        if focused == .teamL {
                            SiteAddScoreChips(scores: loserChipsForTeam(), selected: teamLoserScore) { s in
                                teamLoserScore = s
                                focused = isVollis ? .location : .comment
                            }
                        }
                    }

                    if !isVollis {
                        SiteAddCommentRow(text: $comment, field: .comment, focus: $focused)
                    }
                    SiteAddTextRow(label: "Location (optional)", text: $location, field: .location, focus: $focused, submit: .done, onSubmit: { focused = nil })

                    HStack(spacing: 8) {
                        SiteAddActionButton(title: saving ? "Saving…" : "Save", filled: true, disabled: saving) { Task { await save() } }
                        SiteAddActionButton(title: "Clear") { clearForm() }
                    }

                }
                .disabled(saving)

                if !todayVollisGames.isEmpty {
                    SiteExpandableSection(title: "Vollis games", count: todayVollisGames.count, subtitle: "Today") {
                        ForEach(todayVollisGames) { game in
                            VollisGameRow(game: game)
                        }
                    }
                }
                if !todayGames.isEmpty {
                    SiteContentCard(title: "Today's Games") {
                    ForEach(todayGames) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.gameName ?? "").font(.subheadline.weight(.semibold))
                            Text(g.displayWinners.joined(separator: " ")).foregroundStyle(.green).font(.caption)
                            Text(g.displayLosers.joined(separator: " ")).foregroundStyle(.red).font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                    }
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .sensoryFeedback(.success, trigger: successTick)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    focused = nil
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
        .onAppear { focused = .gameName }
        .onChange(of: gameName) { _, _ in
            if isVollis { configureVollis() }
        }
        .task(id: auth.statsViewRevision) {
            let name = gameName.trimmingCharacters(in: .whitespaces)
            players = []
            guard !name.isEmpty else { return }
            let ordered = isVollis
                ? (try? await PythonAnywhereClient.shared.vollisPlayers())
                : (try? await PythonAnywhereClient.shared.otherGamePlayers(gameName: name))
            guard gameName.trimmingCharacters(in: .whitespaces) == name else { return }
            players = ordered ?? []
        }
        .task(id: auth.statsViewRevision) {
            knownNames = ["Vollis"]
            knownTypes = []
            entryDefaults = [:]
            await loadGameNames()
        }
        .task {
            let year = String(Calendar.current.component(.year, from: Date()))
            let all = (try? await PythonAnywhereClient.shared.otherGames(year: year, preview: false))?.games ?? []
            todayGames = all.filter { siteIsToday(DoublesGame.parseDate($0.gameDateOnly ?? $0.gameDate) ?? .distantPast) }
        }
    }

    private enum Side { case winner, loser }

    private func loadGameNames() async {
        loadingGameNames = true
        gameNamesError = nil
        do {
            let info = try await PythonAnywhereClient.shared.otherGameTypes()
            try Task.checkCancellation()
            var names = ["Vollis"]
            sitePromote(info.names, in: &names)
            knownNames = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            knownTypes = info.types
            entryDefaults = info.defaults
        } catch {
            guard !Task.isCancelled else { return }
            gameNamesError = "Previous game names could not load. You can still type a game name."
        }
        loadingGameNames = false
    }

    @ViewBuilder
    private func playerSlot(side: Side, index: Int) -> some View {
        let field: Field = side == .winner ? .winner(index) : .loser(index)
        let binding = Binding(
            get: { side == .winner ? winners[index] : losers[index] },
            set: { if side == .winner { winners[index] = $0 } else { losers[index] = $0 } }
        )
        SiteAddTextRow(label: side == .winner ? "Winner \(index + 1)" : "Loser \(index + 1)", text: binding, field: field, focus: $focused, submit: .done, onSubmit: {
            focused = nil
        })
        if focused == field {
            SiteAddSuggestionList(names: siteFilterPlayers(players, query: binding.wrappedValue, excluding: winners + losers)) { name in
                binding.wrappedValue = name
                advanceAfterPlayer(side: side, index: index)
            }
        }
        if scoreType == "individual" {
            let scoreField: Field = side == .winner ? .winnerIndiv(index) : .loserIndiv(index)
            let scoreBind = Binding<Int?>(
                get: { side == .winner ? winnerIndiv[index] : loserIndiv[index] },
                set: { if side == .winner { winnerIndiv[index] = $0 } else { loserIndiv[index] = $0 } }
            )
            SiteAddScoreRow(label: "Score", value: scoreBind, field: scoreField, focus: $focused, onSubmit: {
                advanceAfterIndivScore(side: side, index: index)
            })
            if focused == scoreField {
                SiteAddScoreChips(scores: indivChips, selected: scoreBind.wrappedValue) { s in
                    scoreBind.wrappedValue = s
                    advanceAfterIndivScore(side: side, index: index)
                }
            }
        }
    }

    private func advanceAfterPlayer(side: Side, index: Int) {
        if scoreType == "individual" {
            focused = side == .winner ? .winnerIndiv(index) : .loserIndiv(index)
        } else if side == .winner, index + 1 < winners.count {
            focused = .winner(index + 1)
        } else if side == .winner {
            focused = .loser(0)
        } else if index + 1 < losers.count {
            focused = .loser(index + 1)
        } else if scoreType == "team" {
            focused = .teamW
        } else {
            focused = .comment
        }
    }

    private func advanceAfterIndivScore(side: Side, index: Int) {
        if side == .winner, index + 1 < winners.count {
            focused = .winner(index + 1)
        } else if side == .winner {
            focused = .loser(0)
        } else if index + 1 < losers.count {
            focused = .loser(index + 1)
        } else {
            focused = .comment
        }
    }

    private func addSlot(winner: Bool) {
        if winner, winners.count < 15 {
            winners.append(""); winnerIndiv.append(nil)
        } else if !winner, losers.count < 15 {
            losers.append(""); loserIndiv.append(nil)
        }
    }

    private func resizeSlots(winnerCount: Int, loserCount: Int) {
        let w = max(1, min(winnerCount, 15))
        let l = max(1, min(loserCount, 15))
        while winners.count < w { winners.append(""); winnerIndiv.append(nil) }
        while winners.count > w { winners.removeLast(); winnerIndiv.removeLast() }
        while losers.count < l { losers.append(""); loserIndiv.append(nil) }
        while losers.count > l { losers.removeLast(); loserIndiv.removeLast() }
    }

    private func clearPlayers() {
        winners = Array(repeating: "", count: max(winners.count, 1))
        losers = Array(repeating: "", count: max(losers.count, 1))
        winnerIndiv = Array(repeating: nil, count: winners.count)
        loserIndiv = Array(repeating: nil, count: losers.count)
        teamWinnerScore = nil; teamLoserScore = nil; comment = ""
    }

    private func clearForm() {
        clearPlayers()
        gameName = ""
        gameType = ""
        scoreType = "team"
        resizeSlots(winnerCount: 1, loserCount: 1)
        location = siteLastGameLocation()
        error = nil
        focused = .gameName
    }

    private func loserChipsForTeam() -> [Int] {
        if gameType.lowercased().contains("volleyball"), let w = teamWinnerScore {
            return siteLoserScores(winner: w)
        }
        return loserChips
    }

    private func configureVollis() {
        gameType = "Volleyball"
        scoreType = "team"
        resizeSlots(winnerCount: 1, loserCount: 1)
        winnerChips = Array(11...21)
    }

    private func applyGameName(advanceFocus: Bool = true) async {
        let name = gameName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if isVollis {
            gameName = "Vollis"
            configureVollis()
            if advanceFocus { focused = .winner(0) }
            let ordered = (try? await PythonAnywhereClient.shared.vollisPlayers()) ?? []
            guard isVollis else { return }
            players = ordered
            let year = String(Calendar.current.component(.year, from: Date()))
            let games = (try? await PythonAnywhereClient.shared.vollisGames(year: year, preview: false))?.games ?? []
            guard isVollis else { return }
            todayVollisGames = games.filter { siteIsToday($0.date) }
            return
        }
        todayVollisGames = []
        winnerChips = [21, 25, 15, 18, 20]
        loserChips = [19, 23, 12, 16, 17]
        let key = name.lowercased()
        var defaults = entryDefaults[key]
        if defaults == nil, let info = try? await PythonAnywhereClient.shared.otherGameInfo(name: name) {
            defaults = PythonAnywhereClient.OtherGameEntryInfo(
                gameType: info["game_type"] as? String,
                scoreType: info["score_type"] as? String,
                winnerCount: PythonAnywhereClient.jsonIntPublic(info["winner_count"]),
                loserCount: PythonAnywhereClient.jsonIntPublic(info["loser_count"]))
            entryDefaults[key] = defaults
        }
        guard gameName.trimmingCharacters(in: .whitespaces) == name else { return }
        if let info = defaults {
            if let t = info.gameType, !t.isEmpty { gameType = t }
            if let s = info.scoreType, !s.isEmpty { scoreType = s }
            resizeSlots(winnerCount: info.winnerCount ?? 1, loserCount: info.loserCount ?? 1)
            if info.gameType?.lowercased() == "coed" {
                scoreType = "team"
                resizeSlots(winnerCount: 2, loserCount: 2)
            }
        }
        if advanceFocus { focused = .winner(0) }
        if let ordered = try? await PythonAnywhereClient.shared.otherGamePlayers(gameName: name) {
            guard gameName.trimmingCharacters(in: .whitespaces) == name else { return }
            players = ordered
        }
        if let scores = try? await PythonAnywhereClient.shared.otherGameCommonScores(gameName: name) {
            guard gameName.trimmingCharacters(in: .whitespaces) == name else { return }
            if !scores.winners.isEmpty { winnerChips = scores.winners }
            if !scores.losers.isEmpty { loserChips = scores.losers }
            if !scores.winnerIndiv.isEmpty { indivChips = scores.winnerIndiv }
        }
    }

    private func save() async {
        guard !saving else { return }
        let w = winners.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let l = losers.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !gameName.trimmingCharacters(in: .whitespaces).isEmpty, !w.isEmpty, !l.isEmpty else {
            error = "Game name, winners, and losers are required."
            return
        }
        let savingVollis = isVollis
        if savingVollis {
            guard w.count == 1, l.count == 1, w[0] != l[0],
                  let ws = teamWinnerScore, let ls = teamLoserScore, ws > ls else {
                error = "Vollis needs one winner, one different loser, and a higher winner's score."
                return
            }
            scoreType = "team"
        }
        if gameType.isEmpty { gameType = knownTypes.first ?? "Other" }
        var savedGame: SiteSavedGameReceipt?
        saving = true
        banner = nil
        error = nil
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: Any] = [
            "game_date": siteNowString(),
            "game_type": gameType, "game_name": gameName.trimmingCharacters(in: .whitespaces),
            "winners": w, "losers": l,
            "score_type": scoreType,
            "comment": comment,
            "entered_timezone": TimeZone.current.identifier,
            "location": cleanLocation,
        ]
        if scoreType == "team" {
            if let ws = teamWinnerScore { fields["winner_score"] = ws }
            if let ls = teamLoserScore { fields["loser_score"] = ls }
        } else if scoreType == "individual" {
            fields["winner_scores"] = winners.indices.map { winnerIndiv.indices.contains($0) ? (winnerIndiv[$0].map { "\($0)" } ?? "") : "" }
            fields["loser_scores"] = losers.indices.map { loserIndiv.indices.contains($0) ? (loserIndiv[$0].map { "\($0)" } ?? "") : "" }
        }
        focused = nil
        func side(_ names: [String], _ scores: [Int?]) -> String {
            names.indices.compactMap { index in
                let name = names[index].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                if scoreType == "individual", scores.indices.contains(index), let score = scores[index] { return "\(name) (\(score))" }
                return name
            }.joined(separator: ", ")
        }
        savedGame = SiteSavedGameReceipt(title: gameName, status: "Saving…", isSaving: true, winners: side(winners, winnerIndiv),
            losers: side(losers, loserIndiv),
            winnerScore: scoreType == "team" ? teamWinnerScore : nil,
            loserScore: scoreType == "team" ? teamLoserScore : nil,
            location: cleanLocation, comment: savingVollis ? "" : comment)
        if let savedGame { gameSaveStatus(savedGame) }
        do {
            if savingVollis {
                let vollisFields: [String: Any] = [
                    "winner": w[0], "loser": l[0],
                    "winner_score": teamWinnerScore!, "loser_score": teamLoserScore!,
                    "game_date": fields["game_date"]!,
                    "entered_timezone": TimeZone.current.identifier,
                    "location": cleanLocation,
                ]
                try await PythonAnywhereClient.shared.createVollis(vollisFields)
            } else {
                try await PythonAnywhereClient.shared.createOther(fields)
            }
        } catch {
            savedGame?.status = error.localizedDescription
            savedGame?.isSaving = false
            savedGame?.isError = true
            if let savedGame { gameSaveStatus(savedGame) }
            saving = false
            self.error = error.localizedDescription
            return
        }
        // Remember the players actually saved, excluding unused blank slots.
        // The next entry for this game should reflect this result, not the
        // defaults fetched when the form first opened.
        entryDefaults[gameName.trimmingCharacters(in: .whitespaces).lowercased()] =
            PythonAnywhereClient.OtherGameEntryInfo(
                gameType: gameType, scoreType: scoreType,
                winnerCount: w.count, loserCount: l.count)
        sitePromote([gameName], in: &knownNames)
        siteRememberGameLocation(cleanLocation)
        saving = false
        banner = "Game saved"
        successTick += 1
        sitePromote(w + l, in: &players)
        savedGame?.status = "Game saved"
        savedGame?.isSaving = false
        if let savedGame { gameSaveStatus(savedGame) }
        clearForm()
        focused = nil
        let year = String(Calendar.current.component(.year, from: Date()))
        if savingVollis {
            let games = (try? await PythonAnywhereClient.shared.vollisGames(year: year, preview: false))?.games ?? []
            todayVollisGames = games.filter { siteIsToday($0.date) }
        }
        let all = (try? await PythonAnywhereClient.shared.otherGames(year: year, preview: false))?.games ?? []
        todayGames = all.filter { siteIsToday(DoublesGame.parseDate($0.gameDateOnly ?? $0.gameDate) ?? .distantPast) }
    }
}

struct SiteSavedGameReceipt: Identifiable {
    let id = UUID()
    var title: String
    var status = "Game added"
    var isSaving = false
    var isError = false
    var winners: String
    var losers: String
    var winnerScore: Int?
    var loserScore: Int?
    var location: String
    var comment = ""

    var detail: String {
        let wScore = winnerScore.map { " (\($0))" } ?? ""
        let lScore = loserScore.map { " (\($0))" } ?? ""
        return (["\(winners)\(wScore) beat \(losers)\(lScore)"] +
                [location, comment].filter { !$0.isEmpty }).joined(separator: " · ")
    }
}
