import SwiftUI
import Combine
import PhotosUI

struct SiteAddHubView: View {
    @Binding var section: GameSection
    @Binding var doublesEdit: DoublesGame?
    @Binding var vollisEdit: VollisGame?
    @ObservedObject private var auth = SiteAuthManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isLoggedIn {
                    LoginView()
                } else {
                    VStack {
                        Picker("Type", selection: $section) {
                            ForEach(GameSection.allCases) { s in
                                Text(s.title).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        switch section {
                        case .doubles:
                            SiteAddDoublesView(gameToEdit: doublesEdit) {
                                doublesEdit = nil
                            }
                        case .vollis:
                            SiteAddVollisView(gameToEdit: vollisEdit) {
                                vollisEdit = nil
                            }
                        case .other:
                            SiteAddOtherView()
                        }
                    }
                }
            }
            .navigationTitle("Add")
        }
    }
}

struct SiteAddDoublesView: View {
    var gameToEdit: DoublesGame?
    var onDone: () -> Void
    @State private var winner1 = ""
    @State private var winner2 = ""
    @State private var loser1 = ""
    @State private var loser2 = ""
    @State private var winnerScore = "21"
    @State private var loserScore = "19"
    @State private var comments = ""
    @State private var players: [String] = []
    @State private var error: String?
    @State private var saving = false
    @State private var success = false
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = SiteOfflineQueue.shared

    var body: some View {
        Form {
            if success { Text("Game saved.").foregroundStyle(.green) }
            if let error { Text(error).foregroundStyle(.red) }
            playerField("Winner 1", text: $winner1)
            playerField("Winner 2", text: $winner2)
            playerField("Loser 1", text: $loser1)
            playerField("Loser 2", text: $loser2)
            TextField("Winner score", text: $winnerScore).keyboardType(.numberPad)
            TextField("Loser score", text: $loserScore).keyboardType(.numberPad)
            TextField("Comment", text: $comments, axis: .vertical)
            Button(gameToEdit == nil ? "Save game" : "Update game") { Task { await save() } }
                .disabled(saving)
        }
        .task {
            if let g = gameToEdit {
                winner1 = g.winner1 ?? ""; winner2 = g.winner2 ?? ""
                loser1 = g.loser1 ?? ""; loser2 = g.loser2 ?? ""
                winnerScore = String(g.winnerScore ?? 21)
                loserScore = String(g.loserScore ?? 19)
                comments = g.comment
            }
            players = (try? await PythonAnywhereClient.shared.doublesPlayers()) ?? []
        }
        .onChange(of: gameToEdit?.id) { _, _ in
            if let g = gameToEdit {
                winner1 = g.winner1 ?? ""; winner2 = g.winner2 ?? ""
                loser1 = g.loser1 ?? ""; loser2 = g.loser2 ?? ""
                winnerScore = String(g.winnerScore ?? 21)
                loserScore = String(g.loserScore ?? 19)
                comments = g.comment
            }
        }
    }

    @ViewBuilder
    private func playerField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            TextField(title, text: text)
            if !text.wrappedValue.isEmpty {
                ForEach(players.filter { $0.lowercased().contains(text.wrappedValue.lowercased()) }.prefix(6), id: \.self) { name in
                    Button(name) { text.wrappedValue = name }.font(.caption)
                }
            }
        }
    }

    private func save() async {
        guard let ws = Int(winnerScore), let ls = Int(loserScore), ws > ls else {
            error = "Winner score must be greater than loser score."
            return
        }
        let names = [winner1, winner2, loser1, loser2].map { $0.trimmingCharacters(in: .whitespaces) }
        guard Set(names).count == 4, names.allSatisfy({ !$0.isEmpty }) else {
            error = "Four unique player names required."
            return
        }
        saving = true
        error = nil
        let tz = TimeZone.current.identifier
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fields: [String: Any] = [
            "game_date": df.string(from: Date()),
            "winner1": names[0], "winner2": names[1],
            "loser1": names[2], "loser2": names[3],
            "winner_score": ws, "loser_score": ls,
            "comments": comments,
            "entered_timezone": tz,
        ]
        do {
            if !network.isConnected {
                if let g = gameToEdit {
                    queue.enqueue(method: "PUT", path: "/api/doubles/games/\(g.id)", body: fields)
                } else {
                    queue.enqueue(method: "POST", path: "/api/doubles/games", body: fields)
                }
                success = true
            } else if let g = gameToEdit {
                _ = try await PythonAnywhereClient.shared.updateDoubles(id: g.id, fields: fields)
                success = true
                onDone()
            } else {
                _ = try await PythonAnywhereClient.shared.createDoubles(fields)
                success = true
                winner1 = ""; winner2 = ""; loser1 = ""; loser2 = ""; comments = ""
            }
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

struct SiteAddVollisView: View {
    var gameToEdit: VollisGame?
    var onDone: () -> Void
    @State private var winner = ""
    @State private var loser = ""
    @State private var winnerScore = "21"
    @State private var loserScore = "19"
    @State private var error: String?
    @State private var saving = false
    @ObservedObject private var auth = SiteAuthManager.shared

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            TextField("Winner", text: $winner)
            TextField("Loser", text: $loser)
            TextField("Winner score", text: $winnerScore).keyboardType(.numberPad)
            TextField("Loser score", text: $loserScore).keyboardType(.numberPad)
            Button(gameToEdit == nil ? "Save vollis game" : "Update") { Task { await save() } }
                .disabled(saving || !auth.isLoggedIn)
        }
        .task {
            if let g = gameToEdit {
                winner = g.winner ?? ""; loser = g.loser ?? ""
                winnerScore = String(g.winnerScore ?? 21)
                loserScore = String(g.loserScore ?? 19)
            }
        }
    }

    private func save() async {
        guard let ws = Int(winnerScore), let ls = Int(loserScore), ws > ls, winner != loser, !winner.isEmpty else {
            error = "Check names and scores."
            return
        }
        saving = true
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fields: [String: Any] = [
            "game_date": df.string(from: Date()),
            "winner": winner.trimmingCharacters(in: .whitespaces),
            "loser": loser.trimmingCharacters(in: .whitespaces),
            "winner_score": ws, "loser_score": ls,
            "entered_timezone": TimeZone.current.identifier,
        ]
        do {
            if let g = gameToEdit {
                try await PythonAnywhereClient.shared.updateVollis(id: g.id, fields: fields)
                onDone()
            } else {
                try await PythonAnywhereClient.shared.createVollis(fields)
                winner = ""; loser = ""
            }
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

struct SiteAddOtherView: View {
    @State private var gameType = "Cards"
    @State private var gameName = ""
    @State private var winners = ""
    @State private var losers = ""
    @State private var winnerScore = ""
    @State private var loserScore = ""
    @State private var comment = ""
    @State private var scoreType = "team"
    @State private var error: String?
    @State private var saving = false
    @State private var knownNames: [String] = []
    @State private var knownTypes: [String] = []

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            TextField("Game type (e.g. Cards, Volleyball, Coed)", text: $gameType)
            if !knownTypes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(knownTypes, id: \.self) { t in
                            Button(t) { gameType = t }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                }
            }
            TextField("Game name", text: $gameName)
            if !knownNames.isEmpty && !gameName.isEmpty {
                ForEach(knownNames.filter { $0.lowercased().contains(gameName.lowercased()) }.prefix(6), id: \.self) { n in
                    Button(n) { gameName = n }.font(.caption)
                }
            }
            TextField("Winners (comma-separated)", text: $winners)
            TextField("Losers (comma-separated)", text: $losers)
            Picker("Scoring", selection: $scoreType) {
                Text("Team").tag("team")
                Text("Individual").tag("individual")
                Text("None").tag("none")
            }
            if scoreType != "none" {
                TextField("Winner score", text: $winnerScore).keyboardType(.numberPad)
                TextField("Loser score", text: $loserScore).keyboardType(.numberPad)
            }
            TextField("Comment", text: $comment)
            Button("Save other game") { Task { await save() } }.disabled(saving)
        }
        .task {
            if let info = try? await PythonAnywhereClient.shared.otherGameTypes() {
                knownNames = info.names
                knownTypes = info.types
                if let first = info.types.first, gameType == "Cards" { gameType = first }
            }
        }
    }

    private func save() async {
        let w = winners.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let l = losers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !gameType.isEmpty, !gameName.isEmpty, !w.isEmpty, !l.isEmpty else {
            error = "Type, name, winners, and losers are required."
            return
        }
        saving = true
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var fields: [String: Any] = [
            "game_date": df.string(from: Date()),
            "game_type": gameType, "game_name": gameName,
            "winners": w, "losers": l,
            "score_type": scoreType,
            "comment": comment,
            "entered_timezone": TimeZone.current.identifier,
        ]
        if scoreType == "team" {
            if let ws = Int(winnerScore) { fields["winner_score"] = ws }
            if let ls = Int(loserScore) { fields["loser_score"] = ls }
        }
        do {
            try await PythonAnywhereClient.shared.createOther(fields)
            winners = ""; losers = ""; comment = ""
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

struct SitePlayerDetailView: View {
    var name: String
    var year: String
    var section: GameSection
    @State private var payload: DoublesPlayerPayload?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let error { Text(error).foregroundStyle(.red).padding() }
            if let p = payload {
                HStack {
                    AsyncImage(url: URL(string: p.photoUrl ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3)).overlay(Text(String(name.prefix(1))))
                    }
                    .frame(width: 72, height: 72).clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(p.name).font(.title2.bold())
                        if let nick = p.nickname, !nick.isEmpty { Text(nick).foregroundStyle(.secondary) }
                        if let r = p.rating, let rank = p.rank {
                            Text("Rating \(Int(r)) · #\(rank) of \(p.totalRanked ?? 0)")
                        }
                    }
                    Spacer()
                }.padding()
                if let s = p.stats {
                    HStack {
                        stat("W", "\(s.wins)", .green)
                        stat("L", "\(s.losses)", .red)
                        stat("Win%", s.winPctDisplay, nil)
                        if let st = p.currentStreak {
                            stat("Streak", "\(st.length)\(st.type)", st.type == "W" ? .green : .red)
                        }
                    }.padding(.horizontal)
                }
                if let form = p.recentForm, !form.isEmpty {
                    HStack {
                        Text("Last \(form.count)")
                        ForEach(Array(form.enumerated()), id: \.offset) { _, r in
                            Text(r)
                                .font(.caption.bold())
                                .padding(6)
                                .background(r == "W" ? Color.green : Color.red)
                                .foregroundStyle(.black)
                                .clipShape(Circle())
                        }
                    }.padding()
                }
                if let partners = p.partners, !partners.isEmpty {
                    Text("Partners").font(.headline).padding(.horizontal)
                    ForEach(partners) { m in
                        NavigationLink {
                            SitePlayerDetailView(name: m.partner ?? "", year: year, section: section)
                        } label: {
                            HStack {
                                Text(m.partner ?? "")
                                Spacer()
                                Text("\(m.wins)-\(m.losses)  \(Int(m.winPercentage * 100))%")
                            }.padding(.horizontal)
                        }
                    }
                }
                if let opponents = p.opponents, !opponents.isEmpty {
                    Text("Opponents").font(.headline).padding(.horizontal).padding(.top)
                    ForEach(opponents) { m in
                        NavigationLink {
                            SitePlayerDetailView(name: m.opponent ?? "", year: year, section: section)
                        } label: {
                            HStack {
                                Text(m.opponent ?? "")
                                Spacer()
                                Text("\(m.wins)-\(m.losses)  \(Int(m.winPercentage * 100))%")
                            }.padding(.horizontal)
                        }
                    }
                }
                Text("Games").font(.headline).padding()
                if section == .doubles {
                    ForEach(p.games ?? []) { g in
                        DoublesGameRow(game: g).padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle(name)
        .task { await load() }
    }

    private func stat(_ label: String, _ value: String, _ color: Color?) -> some View {
        VStack {
            Text(value).font(.title3.bold()).foregroundStyle(color ?? Color.primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        do {
            switch section {
            case .doubles:
                payload = try await PythonAnywhereClient.shared.doublesPlayer(name: name, year: year)
            case .vollis:
                payload = try await PythonAnywhereClient.shared.vollisPlayer(name: name, year: year)
            case .other:
                payload = try await PythonAnywhereClient.shared.otherPlayer(name: name, year: year)
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct LoginView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            TextField("Username", text: $username).textInputAutocapitalization(.never)
            SecureField("Password", text: $password)
            Button("Sign in") {
                Task {
                    busy = true
                    do {
                        try await auth.login(username: username, password: password)
                    } catch { self.error = error.localizedDescription }
                    busy = false
                }
            }.disabled(busy || username.isEmpty || password.isEmpty)
        }
        .navigationTitle("Login")
    }
}
