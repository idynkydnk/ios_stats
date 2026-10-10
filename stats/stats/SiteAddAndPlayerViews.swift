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
                        switch section {
                        case .doubles:
                            SiteAddDoublesView(gameToEdit: doublesEdit, header: AnyView(addHeader)) {
                                doublesEdit = nil
                            }
                        case .vollis:
                            SiteAddVollisView(gameToEdit: vollisEdit, header: AnyView(addHeader)) {
                                vollisEdit = nil
                                section = .other
                            }
                        case .other:
                            SiteAddOtherView(header: AnyView(addHeader))
                        }
                    }
                }
            }
            .navigationTitle(auth.isLoggedIn ? "" : "Add")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var addHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add")
                .font(.largeTitle.bold())
                .padding(.horizontal)
                .padding(.top, 8)
            Picker("Type", selection: Binding(
                get: { section == .doubles ? GameSection.doubles : .other },
                set: { section = $0 }
            )) {
                Text("Doubles").tag(GameSection.doubles)
                Text("Other").tag(GameSection.other)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .padding(.bottom, 12)
    }
}

struct SitePlayerDetailView: View {
    @Environment(\.siteAppearance) private var appearance
    @AppStorage("stats.doublesDivision") private var division = "open"
    @ScaledMetric(relativeTo: .subheadline) private var statMinimumWidth: CGFloat = 72

    var name: String
    @State private var year: String
    var section: GameSection
    @State private var years: [String] = ["All years"]
    @State private var payload: DoublesPlayerPayload?
    @State private var displayedCacheKey: String?
    @State private var dataRevision = UUID()
    @State private var loading = false
    @State private var loadingMore = false
    @State private var loadID = UUID()
    @State private var error: String?
    @ObservedObject private var auth = SiteAuthManager.shared

    init(name: String, year: String, section: GameSection) {
        self.name = name
        self.section = section
        _year = State(initialValue: year == "All" ? "All years" : year)
    }

    private var cacheKey: String {
        SiteBrowseCache.playerKey(scope: auth.browseCacheScope, section: section.rawValue, year: year, name: name,
                                 division: section == .doubles ? division : "", revision: auth.statsViewRevision)
    }

    var body: some View {
        ScrollView {
            HStack {
                Text("Year").font(.subheadline.weight(.semibold))
                Spacer()
                SiteYearMenu(selectedYear: $year, years: years)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            if let error { Text(error).foregroundStyle(.red).padding() }
            if error == nil && (payload == nil || displayedCacheKey != cacheKey) {
                ProgressView("Loading player…").padding()
            }
            if let p = payload, displayedCacheKey == cacheKey {
                VStack(spacing: 14) {
                    HStack {
                        playerIdentity(p)
                        Spacer()
                    }.padding()
                    Divider().padding(.horizontal, 18)
                    if let s = p.stats {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: statMinimumWidth), spacing: 12)], spacing: 16) {
                            stat("Wins", "\(s.wins)", nil)
                            stat("Losses", "\(s.losses)", nil)
                            stat("Win%", s.winPctDisplay, nil)
                            if let st = p.currentStreak {
                                stat("Streak", "\(st.length)\(st.type)", st.type == "W" ? .green : .red)
                            }
                        }.padding(.horizontal)
                    }
                    if let form = p.recentForm, !form.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last \(form.count)")
                                .fixedSize(horizontal: true, vertical: false)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(form.enumerated()), id: \.offset) { _, r in
                                        Text(r)
                                            .font(.caption.bold())
                                            .padding(6)
                                            .background(r == "W" ? Color.green : Color.red)
                                            .foregroundStyle(.black)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }.padding()
                    }
                }
                .padding(.vertical, 16)
                .modifier(SiteCardSurface())
                .padding(.horizontal)

                if let partners = p.partners, !partners.isEmpty {
                    SiteExpandableSection(title: "Partners", count: partners.count) {
                        SiteLimitedRows(partners) { m in
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
                    SiteExpandableSection(title: "Opponents", count: opponents.count) {
                        SiteLimitedRows(opponents) { m in
                            NavigationLink {
                                SitePlayerDetailView(name: m.opponent ?? "", year: year, section: section)
                            } label: {
                                matchupRow(name: m.opponent ?? "", wins: m.wins, losses: m.losses, winPct: m.winPercentage)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                if section == .doubles {
                    SiteExpandableSection(title: "Games", count: p.gamesTotal ?? (p.games ?? []).count) {
                        if p.gamesTotal != nil {
                            LazyVStack(spacing: 0) {
                                ForEach(p.games ?? []) { g in
                                    DoublesGameRow(game: g, year: year, section: section)
                                }
                            }
                            if p.gamesNextOffset != nil {
                                Button(loadingMore ? "Loading games…" : "Show older games") {
                                    Task { await loadMoreGames() }
                                }
                                .disabled(loading || loadingMore)
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                        } else {
                            SiteLimitedRows(p.games ?? []) { g in
                                DoublesGameRow(game: g, year: year, section: section)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(appearance.background)
        .navigationTitle(name)
        .toolbar {
            if auth.isLoggedIn && !auth.isPreviewing {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit") {
                        SiteEditPlayerView(name: payload?.name ?? name)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                SiteCopyLinkButton(url: SitePublicLink.player(section: section, year: year, name: payload?.name ?? name))
            }
        }
        .task(id: "\(cacheKey)-\(dataRevision)-\(auth.sessionReady)") { await load() }
        .refreshable { await load(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: SiteBrowseCache.didChange, object: SiteBrowseCache.playerDetails)
            .receive(on: RunLoop.main)) { _ in
            dataRevision = UUID()
        }
    }

    @ViewBuilder
    private func playerIdentity(_ p: DoublesPlayerPayload) -> some View {
        if auth.isLoggedIn && !auth.isPreviewing {
            NavigationLink {
                SiteEditPlayerView(name: p.name)
            } label: {
                playerIdentityLabel(p)
            }
            .buttonStyle(.plain)
        } else {
            playerIdentityLabel(p)
        }
    }

    private func playerIdentityLabel(_ p: DoublesPlayerPayload) -> some View {
        HStack {
            SitePlayerAvatar(name: p.name, size: 72, photoUrl: p.photoUrl)
            VStack(alignment: .leading) {
                Text(p.name).font(.title2.bold())
                if let nick = p.nickname, !nick.isEmpty { Text(nick).foregroundStyle(.secondary) }
                if let r = p.rating, let rank = p.rank {
                    Text("Rating \(String(format: "%.2f", r)) · #\(rank) of \(p.totalRanked ?? 0)")
                }
                if auth.isLoggedIn && !auth.isPreviewing {
                    Text("Edit player")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
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
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 16) }
    }

    private func stat(_ label: String, _ value: String, _ color: Color?) -> some View {
        VStack {
            Text(value).font(.title3.bold()).foregroundStyle(color ?? Color.primary)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func load(force: Bool = false) async {
        guard auth.sessionReady else { return }
        let requestedYear = year
        let requestID = UUID()
        loadID = requestID
        let key = cacheKey
        let cache = SiteBrowseCache.playerDetails
        let generation = cache.generation
        let cached = cache.load(DoublesPlayerPayload.self, key: key)
        if displayedCacheKey != key || payload == nil {
            payload = cached?.value
            displayedCacheKey = key
            years = ["All years"] + (payload?.allYears ?? []).filter { $0 != "All years" && $0 != "All" }
        }
        error = nil
        loading = false
        if !force, cached?.isFresh() == true { return }
        loading = true
        defer { if loadID == requestID { loading = false } }
        do {
            let result: DoublesPlayerPayload
            switch section {
            case .doubles:
                result = try await PythonAnywhereClient.shared.doublesPlayer(name: name, year: requestedYear)
            case .vollis:
                result = try await PythonAnywhereClient.shared.vollisPlayer(name: name, year: requestedYear)
            case .other:
                result = try await PythonAnywhereClient.shared.otherPlayer(name: name, year: requestedYear)
            }
            guard !Task.isCancelled, loadID == requestID, cacheKey == key, cache.generation == generation else { return }
            payload = result
            years = ["All years"] + result.allYears.filter { $0 != "All years" && $0 != "All" }
            cache.save(result, key: key, generation: generation)
        } catch {
            guard !Task.isCancelled, loadID == requestID, cacheKey == key else { return }
            self.error = payload == nil ? error.localizedDescription : "Showing saved results. " + error.localizedDescription
        }
    }

    @MainActor
    private func loadMoreGames() async {
        guard !loadingMore, !loading, let offset = payload?.gamesNextOffset else { return }
        let key = cacheKey
        let requestID = loadID
        let generation = SiteBrowseCache.playerDetails.generation
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = try await PythonAnywhereClient.shared.doublesPlayer(name: name, year: year, gameOffset: offset)
            guard !Task.isCancelled, cacheKey == key, loadID == requestID,
                  SiteBrowseCache.playerDetails.generation == generation else { return }
            let existingIDs = Set((payload?.games ?? []).map(\.id))
            payload?.games = (payload?.games ?? []) + (next.games ?? []).filter { !existingIDs.contains($0.id) }
            payload?.gamesTotal = next.gamesTotal
            payload?.gamesNextOffset = next.gamesNextOffset
            error = nil
        } catch {
            guard !Task.isCancelled, cacheKey == key, loadID == requestID else { return }
            self.error = "Could not load older games. " + error.localizedDescription
        }
    }
}

struct LoginView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var registering = true
    @StateObject private var google = SiteGoogleSignIn()
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Picker("Account", selection: $registering) {
                    Text("Create account").tag(true)
                    Text("Sign in").tag(false)
                }.pickerStyle(.segmented)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let message = auth.lastError { Text(message).foregroundStyle(.red) }
            Section {
            TextField("Username", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(registering ? .newPassword : .password)
            if registering {
                SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
            }
            Button(busy ? "Please wait..." : (registering ? "Create account" : "Sign in")) {
                Task { await signIn() }
            }
            .disabled(busy || username.isEmpty || password.isEmpty || (registering && (password.count < 12 || password != confirmation)))
            } footer: {
                if registering { Text("Use at least 12 characters for your password.") }
            }
            Section {
                SiteAppleSignInButton(busy: $busy, error: $error)
                Button {
                    Task {
                        busy = true
                        error = nil
                        auth.lastError = nil
                        do { try await google.signIn(); dismiss() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("G").font(.title3.weight(.bold)).foregroundStyle(Color.blue)
                        Text("Continue with Google").font(.system(size: 17, weight: .medium))
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
        }
        .navigationTitle("Welcome to Stats")
        .onChange(of: registering) { _, _ in error = nil; auth.lastError = nil }
    }

    private func signIn() async {
        busy = true
        error = nil
        auth.lastError = nil
        do {
            try await auth.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password, registering: registering)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
