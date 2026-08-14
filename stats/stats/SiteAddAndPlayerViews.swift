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
                    VStack(spacing: 0) {
                        Picker("Type", selection: $section) {
                            ForEach(GameSection.allCases) { s in
                                Text(s.title).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                addLink("AI Summary", systemImage: "sparkles") { SiteAISummaryView() }
                                addLink("Flyer", systemImage: "megaphone") { SiteFlyerView() }
                                addLink("Recaps", systemImage: "text.bubble") { SiteRecapsView() }
                                addLink("Voice", systemImage: "mic") { SiteVoiceAddView() }
                                addLink("Tournament", systemImage: "trophy") { SiteTournamentsView() }
                                addLink("Player", systemImage: "person.badge.plus") { SitePlayersView() }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }

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

    private func addLink<V: View>(_ title: String, systemImage: String, @ViewBuilder destination: () -> V) -> some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                    SitePlayerAvatar(name: p.name, size: 72)
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
                    VStack(spacing: 10) {
                        ForEach(partners) { m in
                            NavigationLink {
                                SitePlayerDetailView(name: m.partner ?? "", year: year, section: section)
                            } label: {
                                matchupRow(name: m.partner ?? "", wins: m.wins, losses: m.losses, winPct: m.winPercentage)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                if let opponents = p.opponents, !opponents.isEmpty {
                    Text("Opponents").font(.headline).padding(.horizontal).padding(.top)
                    VStack(spacing: 10) {
                        ForEach(opponents) { m in
                            NavigationLink {
                                SitePlayerDetailView(name: m.opponent ?? "", year: year, section: section)
                            } label: {
                                matchupRow(name: m.opponent ?? "", wins: m.wins, losses: m.losses, winPct: m.winPercentage)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                Text("Games").font(.headline).padding(.horizontal).padding(.top)
                if section == .doubles {
                    VStack(spacing: 12) {
                        ForEach(p.games ?? []) { g in
                            DoublesGameRow(game: g)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SiteCopyLinkButton(url: SitePublicLink.player(section: section, year: payload?.year ?? year, name: payload?.name ?? name))
            }
        }
        .task { await load() }
    }

    private func matchupRow(name: String, wins: Int, losses: Int, winPct: Double) -> some View {
        let pct = winPct <= 1.0 ? winPct * 100 : winPct
        return HStack(alignment: .center, spacing: 12) {
            Text(name)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(wins)-\(losses)")
                .monospacedDigit()
                .frame(width: 56, alignment: .leading)
            Text(String(format: "%.0f%%", pct))
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
