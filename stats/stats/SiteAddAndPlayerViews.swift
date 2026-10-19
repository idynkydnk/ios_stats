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
        let loadStarted = Date()
        defer { SitePerformance.record("player-load", since: loadStarted) }
        guard auth.sessionReady else { return }
        let requestedYear = year
        let requestID = UUID()
        loadID = requestID
        let key = cacheKey
        let cache = SiteBrowseCache.playerDetails
        let generation = cache.generation
        let cached = await cache.loadAsync(DoublesPlayerPayload.self, key: key)
        guard !Task.isCancelled, loadID == requestID, cache.generation == generation else { return }
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
            await cache.saveAsync(result, key: key, generation: generation)
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
    @StateObject private var flow = SiteEmailSignIn(baseURL: PythonAnywhereClient.shared.baseURL)
    @State private var email = ""
    @State private var code = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    @State private var requestTask: Task<Void, Never>?
    @FocusState private var focused: Field?
    private enum Field { case email, code, firstName, lastName }
    private var enrolling: Bool { flow.state?.enrolling == true }

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red).accessibilityLabel("Sign-in error: " + error) }
            if auth.biometricEnabled && !auth.isLoggedIn {
                Section {
                    Button {
                        guard !busy else { return }
                        busy = true
                        error = nil
                        requestTask = Task { @MainActor in
                            defer { busy = false }
                            do {
                                try await auth.loginWithBiometrics()
                                dismiss()
                            } catch is CancellationError {
                            } catch {
                                self.error = "Couldn’t sign in with \(auth.biometricName). Try again or use email below."
                            }
                        }
                    } label: {
                        Label("Sign in with \(auth.biometricName)",
                              systemImage: auth.biometricName == "Touch ID" ? "touchid" : "faceid")
                    }
                }
            }
            if let state = flow.state {
                switch state.step {
                case .email:
                    Section {
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused, equals: .email)
                            .submitLabel(.go).onSubmit { sendCode() }
                        Button("Email me a code", action: sendCode)
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: { Text(enrolling ? "Add your email" : "Sign in or create an account") }
                    footer: {
                        Text(enrolling ? "Verify your email to keep your existing account and stats. Next time, use a short code instead of a password." : "We’ll email you a four-digit code. New here? Verify your email, then add your first and last name.")
                    }
                    if !enrolling {
                        Section {
                            DisclosureGroup("Use my existing password", isExpanded: $showPassword) {
                                TextField("Username", text: $username)
                                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                                SecureField("Password", text: $password).textContentType(.password)
                                Button("Sign in with password") {
                                    submit(["action": "password", "username": username.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
                                }.disabled(username.isEmpty || password.isEmpty)
                                Text("If your account has no email yet, we’ll ask you to add one after signing in. Contact Kyle if you can’t access your old account.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                case .code:
                    Section {
                        Text("Enter the four-digit code sent to \(state.email ?? email).")
                        TextField("4-digit code", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .font(.title2.monospacedDigit()).focused($focused, equals: .code)
                            .onChange(of: code) { _, value in
                                code = String(value.filter { "0123456789".contains($0) }.prefix(4))
                            }
                        Button("Continue") { submit(["action": "verify", "code": code]) }
                            .disabled(code.count != 4)
                    } header: { Text("Check your email") }
                    footer: { Text("Your code expires in five minutes. Check your spam folder if you don’t see it.") }
                    Section {
                        Button("Send a new code") { code = ""; submit(["action": "resend"]) }
                        Button("Use a different email") { code = ""; submit(["action": "change"]) }
                    } footer: { Text("Wait a minute before requesting another code.") }
                case .signup:
                    Section {
                        TextField("First name", text: $firstName)
                            .textContentType(.givenName).textInputAutocapitalization(.words)
                            .autocorrectionDisabled().focused($focused, equals: .firstName)
                            .submitLabel(.next).onSubmit { focused = .lastName }
                        TextField("Last name", text: $lastName)
                            .textContentType(.familyName).textInputAutocapitalization(.words)
                            .autocorrectionDisabled().focused($focused, equals: .lastName)
                        Button("Create account") {
                            submit(["action": "signup", "first_name": firstName, "last_name": lastName])
                        }.disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: { Text("What’s your name?") }
                    footer: { Text("Your email is verified. Add your name to finish. We’ll tidy up capitalization for you.") }
                    Section {
                        Button("Use my existing account") {
                            showPassword = true
                            submit(["action": "change", "password_start": "1"])
                        }
                    } footer: { Text("Already have stats in an account without an email? Use your old password first to keep them.") }
                case .complete:
                    Button("Finish signing in") { submit() }
                case nil:
                    Button("Try again") { submit() }
                }
            } else if !busy {
                Button("Try again") { submit(bearer: auth.token) }
            }
            if busy { ProgressView("Please wait…") }
            if auth.isLoggedIn && enrolling {
                Button("Log out", role: .destructive) { Task { await auth.logout() } }
            }
        }
        .disabled(busy)
        .navigationTitle(enrolling ? "Add your email" : "Welcome to Stats")
        .task { if flow.state == nil { await perform(bearer: auth.token) } }
        .onDisappear { requestTask?.cancel() }
    }

    private func sendCode() {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit(["action": "send", "email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    private func submit(_ fields: [String: String]? = nil, bearer: String? = nil) {
        guard !busy else { return }
        focused = nil
        requestTask = Task { await perform(fields, bearer: bearer) }
    }

    @MainActor
    private func perform(_ fields: [String: String]? = nil, bearer: String? = nil) async {
        guard !busy else { return }
        busy = true
        error = nil
        auth.lastError = nil
        defer { busy = false }
        do {
            if let token = try await flow.request(fields, bearer: bearer) {
                try Task.checkCancellation()
                try await auth.loginWithEmailToken(token)
                dismiss()
            } else {
                switch flow.state?.step {
                case .email: focused = .email
                case .code: focused = .code
                case .signup: focused = .firstName
                default: break
                }
            }
        } catch is CancellationError {
            // Closing sign-in leaves the existing account untouched.
        } catch {
            self.error = error.localizedDescription
        }
    }
}
