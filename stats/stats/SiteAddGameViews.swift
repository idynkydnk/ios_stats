import SwiftUI
import Speech
import AVFoundation

struct SiteAddDoublesView: View {
    var gameToEdit: DoublesGame?
    var onDone: () -> Void

    enum Field: Hashable {
        case w1, w2, l1, l2, wScore, lScore, comment
    }

    @State private var winner1 = ""
    @State private var winner2 = ""
    @State private var loser1 = ""
    @State private var loser2 = ""
    @State private var winnerScore: Int?
    @State private var loserScore: Int?
    @State private var comments = ""
    @State private var players: [String] = []
    @State private var error: String?
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var saving = false
    @State private var successTick = 0
    @State private var rematch: (String, String, String, String)?
    @State private var today: TodaysDoublesDashboard?
    @State private var showVoice = false
    @FocusState private var focused: Field?
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = SiteOfflineQueue.shared

    private let winnerChips = [21, 15, 22, 23, 16]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner {
                        SiteAddBanner(text: banner, isError: bannerIsError)
                    }
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

                    SiteAddTextRow(label: "Comment (optional)", text: $comments, field: .comment, focus: $focused, submit: .done, onSubmit: { focused = nil })

                    HStack(spacing: 8) {
                        SiteAddActionButton(title: gameToEdit == nil ? "Save" : "Update", filled: true, disabled: saving) {
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

                    if let today, !today.stats.isEmpty || !today.games.isEmpty {
                        todayBoard(today)
                    }
                }
                .padding()
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focused) { _, new in
                if let new {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showVoice = true } label: { Image(systemName: "mic.fill") }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .sheet(isPresented: $showVoice) {
            SiteAddVoiceSheet { parsed in
                applyParsed(parsed)
                showVoice = false
            }
        }
        .task { await bootstrap() }
        .onChange(of: gameToEdit?.id) { _, _ in applyEdit() }
        .onAppear {
            if gameToEdit == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .w1 }
            }
        }
    }

    @ViewBuilder
    private func playerRow(_ label: String, text: Binding<String>, field: Field, next: Field) -> some View {
        SiteAddTextRow(label: label, text: text, field: field, focus: $focused, onSubmit: {
            if gameToEdit == nil { advance(to: next) } else { focused = nil }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Stats").font(.headline).padding(.top, 8)
            ForEach(Array(dash.stats.enumerated()), id: \.element.id) { idx, row in
                HStack {
                    Text("\(idx + 1)").foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
                    Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
                    if let pm = row.plusMinus {
                        Text(pm > 0 ? "+\(pm)" : "\(pm)")
                            .foregroundStyle(pm >= 0 ? Color.green : Color.red)
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text("\(row.wins)").foregroundStyle(.green).frame(width: 28, alignment: .trailing)
                    Text("\(row.losses)").foregroundStyle(.red).frame(width: 28, alignment: .trailing)
                    Text(row.winPctDisplay).frame(width: 44, alignment: .trailing)
                }
                .font(.subheadline)
            }
            Text("Today's Games").font(.headline).padding(.top, 8)
            if dash.games.isEmpty {
                Text("No doubles played today yet.").foregroundStyle(.secondary)
            } else {
                ForEach(dash.games) { g in
                    DoublesGameRow(game: g)
                        .padding(.vertical, 4)
                }
            }
        }
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
        players = (try? await PythonAnywhereClient.shared.doublesPlayers()) ?? []
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
        error = nil
        if focusFirst { focused = .w1 }
    }

    private func applyParsed(_ parsed: [String: Any]) {
        if let v = parsed["winner1"] as? String { winner1 = v }
        if let v = parsed["winner2"] as? String { winner2 = v }
        if let v = parsed["loser1"] as? String { loser1 = v }
        if let v = parsed["loser2"] as? String { loser2 = v }
        winnerScore = parsed["winner_score"] as? Int ?? Int("\(parsed["winner_score"] ?? "")")
        loserScore = parsed["loser_score"] as? Int ?? Int("\(parsed["loser_score"] ?? "")")
        focused = .comment
    }

    private func save() async {
        guard let ws = winnerScore, let ls = loserScore, ws > ls else {
            error = "Winner score must be greater than loser score."
            return
        }
        let names = [winner1, winner2, loser1, loser2].map { $0.trimmingCharacters(in: .whitespaces) }
        guard Set(names.map { $0.lowercased() }).count == 4, names.allSatisfy({ !$0.isEmpty }) else {
            error = "Four unique player names required."
            return
        }
        saving = true
        error = nil
        let snapshot = (winner1, winner2, loser1, loser2, winnerScore, loserScore, comments)
        let fields: [String: Any] = [
            "game_date": siteNowString(),
            "winner1": names[0], "winner2": names[1],
            "loser1": names[2], "loser2": names[3],
            "winner_score": ws, "loser_score": ls,
            "comments": comments,
            "entered_timezone": TimeZone.current.identifier,
        ]
        rematch = (names[0], names[1], names[2], names[3])
        sitePromote(names, in: &players)
        if gameToEdit == nil {
            banner = "Game added"
            bannerIsError = false
            successTick += 1
            clearForm(focusFirst: true)
        }
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
                onDone()
            } else {
                _ = try await PythonAnywhereClient.shared.createDoubles(fields)
                banner = "Game saved"
            }
            players = (try? await PythonAnywhereClient.shared.doublesPlayers()) ?? players
            await refreshToday()
        } catch {
            if gameToEdit == nil {
                winner1 = snapshot.0; winner2 = snapshot.1; loser1 = snapshot.2; loser2 = snapshot.3
                winnerScore = snapshot.4; loserScore = snapshot.5; comments = snapshot.6
            }
            banner = nil
            self.error = error.localizedDescription
        }
        saving = false
    }
}

struct SiteAddVollisView: View {
    var gameToEdit: VollisGame?
    var onDone: () -> Void

    enum Field: Hashable { case winner, loser, wScore, lScore }

    @State private var winner = ""
    @State private var loser = ""
    @State private var winnerScore: Int?
    @State private var loserScore: Int?
    @State private var players: [String] = []
    @State private var todayGames: [VollisGame] = []
    @State private var error: String?
    @State private var banner: String?
    @State private var saving = false
    @State private var successTick = 0
    @FocusState private var focused: Field?
    @ObservedObject private var auth = SiteAuthManager.shared

    private let winnerChips = Array(11...21)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner { SiteAddBanner(text: banner) }
                    if let error { SiteAddBanner(text: error, isError: true) }

                    SiteAddTextRow(label: "Winner", text: $winner, field: .winner, focus: $focused, onSubmit: {
                        if gameToEdit == nil { focused = .loser }
                    })
                    if focused == .winner {
                        SiteAddSuggestionList(names: siteFilterPlayers(players, query: winner, excluding: [loser])) { name in
                            winner = name
                            if gameToEdit == nil { focused = .loser }
                        }
                    }

                    SiteAddTextRow(label: "Loser", text: $loser, field: .loser, focus: $focused, onSubmit: {
                        if gameToEdit == nil { focused = .wScore }
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

                    SiteAddScoreRow(label: "Loser's score", value: $loserScore, field: .lScore, focus: $focused, submit: .done, onSubmit: { focused = nil })
                    if focused == .lScore {
                        SiteAddScoreChips(scores: siteLoserScores(winner: winnerScore ?? 11), selected: loserScore) { s in
                            loserScore = s
                            focused = nil
                        }
                    }

                    HStack(spacing: 8) {
                        SiteAddActionButton(title: gameToEdit == nil ? "Save" : "Update", filled: true, disabled: saving || !auth.isLoggedIn) {
                            Task { await save() }
                        }
                        SiteAddActionButton(title: "Clear") {
                            winner = ""; loser = ""; winnerScore = nil; loserScore = nil; focused = .winner
                        }
                    }

                    if !todayGames.isEmpty {
                        Text("Today's Games").font(.headline).padding(.top, 8)
                        ForEach(todayGames) { g in
                            HStack {
                                Text("\(g.winner ?? "")  \(g.winnerScore ?? 0)").foregroundStyle(.green)
                                Spacer()
                                Text("\(g.loserScore ?? 0)  \(g.loser ?? "")").foregroundStyle(.red)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding()
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focused) { _, new in
                if let new { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) } }
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task { await load() }
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
        }
        players = (try? await PythonAnywhereClient.shared.vollisPlayers()) ?? []
        let year = String(Calendar.current.component(.year, from: Date()))
        let all = (try? await PythonAnywhereClient.shared.vollisGames(year: year))?.games ?? []
        todayGames = all.filter { siteIsToday($0.date) }
    }

    private func save() async {
        let w = winner.trimmingCharacters(in: .whitespaces)
        let l = loser.trimmingCharacters(in: .whitespaces)
        guard let ws = winnerScore, let ls = loserScore, ws > ls, w != l, !w.isEmpty, !l.isEmpty else {
            error = "Check names and scores."
            return
        }
        saving = true
        error = nil
        let fields: [String: Any] = [
            "game_date": siteNowString(),
            "winner": w, "loser": l,
            "winner_score": ws, "loser_score": ls,
            "entered_timezone": TimeZone.current.identifier,
        ]
        do {
            if let g = gameToEdit {
                try await PythonAnywhereClient.shared.updateVollis(id: g.id, fields: fields)
                banner = "Game saved"
                onDone()
            } else {
                try await PythonAnywhereClient.shared.createVollis(fields)
                banner = "Game saved"
                successTick += 1
                sitePromote([w, l], in: &players)
                winner = ""; loser = ""; winnerScore = nil; loserScore = nil
                focused = .winner
                await load()
            }
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

struct SiteAddOtherView: View {
    enum Field: Hashable {
        case gameName, winner(Int), loser(Int), winnerIndiv(Int), loserIndiv(Int), teamW, teamL, comment
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
    @State private var knownNames: [String] = []
    @State private var knownTypes: [String] = []
    @State private var players: [String] = []
    @State private var winnerChips: [Int] = [21, 25, 15, 18, 20]
    @State private var loserChips: [Int] = [19, 23, 12, 16, 17]
    @State private var indivChips: [Int] = Array(0...10)
    @State private var error: String?
    @State private var banner: String?
    @State private var saving = false
    @State private var successTick = 0
    @State private var todayGames: [OtherGame] = []
    @FocusState private var focused: Field?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner { SiteAddBanner(text: banner) }
                    if let error { SiteAddBanner(text: error, isError: true) }

                    SiteAddTextRow(label: "Game name", text: $gameName, field: .gameName, focus: $focused, onSubmit: {
                        Task { await applyGameName() }
                    }, onFocus: {})
                    if focused == .gameName {
                        SiteAddSuggestionList(names: siteFilterPlayers(knownNames, query: gameName, excluding: [])) { name in
                            gameName = name
                            Task { await applyGameName() }
                        }
                    }

                    if !knownTypes.isEmpty {
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

                    Picker("Scoring", selection: $scoreType) {
                        Text("Team").tag("team")
                        Text("Individual").tag("individual")
                        Text("None").tag("none")
                    }
                    .pickerStyle(.segmented)

                    Text("Winners").font(.headline)
                    ForEach(winners.indices, id: \.self) { i in
                        playerSlot(side: .winner, index: i)
                    }
                    Button("Add winner") { addSlot(winner: true) }
                        .font(.subheadline)

                    Text("Losers").font(.headline)
                    ForEach(losers.indices, id: \.self) { i in
                        playerSlot(side: .loser, index: i)
                    }
                    Button("Add loser") { addSlot(winner: false) }
                        .font(.subheadline)

                    if scoreType == "team" {
                        SiteAddScoreRow(label: "Winner score", value: $teamWinnerScore, field: .teamW, focus: $focused, onSubmit: { focused = .teamL })
                        if focused == .teamW {
                            SiteAddScoreChips(scores: winnerChips, selected: teamWinnerScore) { s in
                                teamWinnerScore = s
                                focused = .teamL
                            }
                        }
                        SiteAddScoreRow(label: "Loser score", value: $teamLoserScore, field: .teamL, focus: $focused, submit: .next, onSubmit: { focused = .comment })
                        if focused == .teamL {
                            SiteAddScoreChips(scores: loserChipsForTeam(), selected: teamLoserScore) { s in
                                teamLoserScore = s
                                focused = .comment
                            }
                        }
                    }

                    SiteAddTextRow(label: "Comment (optional)", text: $comment, field: .comment, focus: $focused, submit: .done, onSubmit: { focused = nil })

                    HStack(spacing: 8) {
                        SiteAddActionButton(title: "Save", filled: true, disabled: saving) { Task { await save() } }
                        SiteAddActionButton(title: "Clear") { clearPlayers(); focused = .gameName }
                    }

                    if !todayGames.isEmpty {
                        Text("Today's Games").font(.headline).padding(.top, 8)
                        ForEach(todayGames) { g in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.gameName ?? "").font(.subheadline.weight(.semibold))
                                Text(g.displayWinners.joined(separator: ", ")).foregroundStyle(.green).font(.caption)
                                Text(g.displayLosers.joined(separator: ", ")).foregroundStyle(.red).font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focused) { _, new in
                if let new { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) } }
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task {
            if let info = try? await PythonAnywhereClient.shared.otherGameTypes() {
                knownNames = info.names
                knownTypes = info.types
            }
            players = knownNames
            let year = String(Calendar.current.component(.year, from: Date()))
            let all = (try? await PythonAnywhereClient.shared.otherGames(year: year))?.games ?? []
            todayGames = all.filter { siteIsToday(DoublesGame.parseDate($0.gameDateOnly ?? $0.gameDate) ?? .distantPast) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .gameName }
        }
    }

    private enum Side { case winner, loser }

    @ViewBuilder
    private func playerSlot(side: Side, index: Int) -> some View {
        let field: Field = side == .winner ? .winner(index) : .loser(index)
        let binding = Binding(
            get: { side == .winner ? winners[index] : losers[index] },
            set: { if side == .winner { winners[index] = $0 } else { losers[index] = $0 } }
        )
        SiteAddTextRow(label: side == .winner ? "Winner \(index + 1)" : "Loser \(index + 1)", text: binding, field: field, focus: $focused, onSubmit: {
            advanceAfterPlayer(side: side, index: index)
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

    private func loserChipsForTeam() -> [Int] {
        if gameType.lowercased().contains("volleyball"), let w = teamWinnerScore {
            return siteLoserScores(winner: w)
        }
        return loserChips
    }

    private func applyGameName() async {
        let name = gameName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let info = try? await PythonAnywhereClient.shared.otherGameInfo(name: name) {
            if let t = info["game_type"] as? String, !t.isEmpty { gameType = t }
            if let s = info["score_type"] as? String, !s.isEmpty { scoreType = s }
            let wc = PythonAnywhereClient.jsonIntPublic(info["winner_count"]) ?? 1
            let lc = PythonAnywhereClient.jsonIntPublic(info["loser_count"]) ?? 1
            resizeSlots(winnerCount: wc, loserCount: lc)
            if (info["game_type"] as? String)?.lowercased() == "coed" {
                scoreType = "team"
                resizeSlots(winnerCount: 2, loserCount: 2)
            }
        }
        if let ordered = try? await PythonAnywhereClient.shared.otherGamePlayers(gameName: name), !ordered.isEmpty {
            players = ordered
        }
        if let scores = try? await PythonAnywhereClient.shared.otherGameCommonScores(gameName: name) {
            if !scores.winners.isEmpty { winnerChips = scores.winners }
            if !scores.losers.isEmpty { loserChips = scores.losers }
            if !scores.winnerIndiv.isEmpty { indivChips = scores.winnerIndiv }
        }
        focused = .winner(0)
    }

    private func save() async {
        let w = winners.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let l = losers.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !gameName.trimmingCharacters(in: .whitespaces).isEmpty, !w.isEmpty, !l.isEmpty else {
            error = "Game name, winners, and losers are required."
            return
        }
        if gameType.isEmpty { gameType = knownTypes.first ?? "Other" }
        saving = true
        error = nil
        var fields: [String: Any] = [
            "game_date": siteNowString(),
            "game_type": gameType, "game_name": gameName.trimmingCharacters(in: .whitespaces),
            "winners": w, "losers": l,
            "score_type": scoreType,
            "comment": comment,
            "entered_timezone": TimeZone.current.identifier,
        ]
        if scoreType == "team" {
            if let ws = teamWinnerScore { fields["winner_score"] = ws }
            if let ls = teamLoserScore { fields["loser_score"] = ls }
        } else if scoreType == "individual" {
            fields["winner_scores"] = winners.indices.map { winnerIndiv.indices.contains($0) ? (winnerIndiv[$0].map { "\($0)" } ?? "") : "" }
            fields["loser_scores"] = losers.indices.map { loserIndiv.indices.contains($0) ? (loserIndiv[$0].map { "\($0)" } ?? "") : "" }
        }
        do {
            try await PythonAnywhereClient.shared.createOther(fields)
            banner = "Game saved"
            successTick += 1
            sitePromote(w + l, in: &players)
            clearPlayers()
            focused = .winner(0)
            let year = String(Calendar.current.component(.year, from: Date()))
            let all = (try? await PythonAnywhereClient.shared.otherGames(year: year))?.games ?? []
            todayGames = all.filter { siteIsToday(DoublesGame.parseDate($0.gameDateOnly ?? $0.gameDate) ?? .distantPast) }
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

struct SiteAddVoiceSheet: View {
    var onFill: ([String: Any]) -> Void
    @StateObject private var capture = VoiceCapture()
    @State private var status = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Speak a result like “Kyle and Aaron beat Dan and Ryan 21 15”.")
                TextEditor(text: $capture.transcript)
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                Button(capture.isRecording ? "Stop" : "Record") { Task { await capture.toggle() } }
                    .buttonStyle(.borderedProminent)
                    .tint(SiteAddAccent.orange)
                Button("Use this") { Task { await parse() } }
                    .disabled(capture.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(status.isEmpty ? capture.status : status).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Voice")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                SFSpeechRecognizer.requestAuthorization { _ in }
                AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            }
        }
    }

    private func parse() async {
        do {
            let parsed = try await PythonAnywhereClient.shared.parseVoice(transcript: capture.transcript)
            onFill(parsed)
        } catch {
            status = error.localizedDescription
        }
    }
}
