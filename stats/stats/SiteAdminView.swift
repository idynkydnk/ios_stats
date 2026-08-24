import SwiftUI
import Combine

enum AdminPane: String, CaseIterable, Identifiable {
    case overview, activity, users
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .activity: return "Activity"
        case .users: return "Users"
        }
    }
}

enum AdminTime {
    private static let utc: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    static func date(from raw: String?) -> Date? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "T", with: " ")
        if let dot = s.firstIndex(of: ".") { s = String(s[..<dot]) }
        if s.count > 19 { s = String(s.prefix(19)) }
        return utc.date(from: s)
    }

    static func relative(_ raw: String?) -> String {
        guard let d = date(from: raw) else { return raw ?? "—" }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: d, relativeTo: Date())
    }

    static func full(_ raw: String?) -> String {
        guard let d = date(from: raw) else { return raw ?? "—" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: d)
    }
}

@MainActor
final class AdminDashboardModel: ObservableObject {
    @Published var pane: AdminPane = .overview
    @Published var overview: AdminOverview?
    @Published var entries: [AdminActivityEntry] = []
    @Published var activityPage = 1
    @Published var activityTotal = 0
    @Published var hasMoreActivity = false
    @Published var search = ""
    @Published var filterUsername: String?
    @Published var actionFilter: String?
    @Published var loading = false
    @Published var loadingMore = false
    @Published var busy = false
    @Published var banner: String?
    @Published var bannerIsError = false
    @Published var loadError: String?
    @Published var pendingUndo: AdminActivityEntry?
    @Published var pendingToggle: SiteUser?
    @Published var resetTarget: SiteUser?
    @Published var resetPassword = ""
    @Published var newUsername = ""
    @Published var newPassword = ""
    @Published var newIsAdmin = false

    var users: [SiteUser] { overview?.users ?? [] }
    var emailConfigured: Bool { overview?.emailConfigured == true }

    var hasActivityFilters: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
            || filterUsername != nil
            || actionFilter != nil
    }

    func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            async let overviewReq = PythonAnywhereClient.shared.adminOverview()
            async let activityReq = PythonAnywhereClient.shared.adminActivity(
                page: 1,
                query: search,
                username: filterUsername,
                action: actionFilter
            )
            let loadedOverview = try await overviewReq
            let loadedActivity = try await activityReq
            overview = loadedOverview
            applyActivityPage(loadedActivity, append: false)
        } catch {
            loadError = error.localizedDescription
            flash(error.localizedDescription, error: true)
        }
    }

    func reloadActivity() async {
        do {
            let page = try await PythonAnywhereClient.shared.adminActivity(
                page: 1,
                query: search,
                username: filterUsername,
                action: actionFilter
            )
            applyActivityPage(page, append: false)
        } catch {
            flash(error.localizedDescription, error: true)
        }
    }

    func loadMoreActivity() async {
        guard hasMoreActivity, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await PythonAnywhereClient.shared.adminActivity(
                page: activityPage + 1,
                query: search,
                username: filterUsername,
                action: actionFilter
            )
            applyActivityPage(page, append: true)
        } catch {
            flash(error.localizedDescription, error: true)
        }
    }

    func showActivity(username: String? = nil, action: String? = nil, search: String = "") {
        filterUsername = username
        actionFilter = action
        self.search = search
        pane = .activity
        Task { await reloadActivity() }
    }

    func clearActivityFilters() {
        search = ""
        filterUsername = nil
        actionFilter = nil
        Task { await reloadActivity() }
    }

    func setQuickFilter(_ query: String) {
        filterUsername = nil
        actionFilter = nil
        search = query
        pane = .activity
        Task { await reloadActivity() }
    }

    func undo(_ entry: AdminActivityEntry) async {
        pendingUndo = nil
        await run {
            let message = try await PythonAnywhereClient.shared.adminUndo(id: entry.id)
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[i].undone = true
                entries[i].undoable = false
            }
            flash(message)
            await loadAll()
        }
    }

    func backup() async {
        await run {
            let filename = try await PythonAnywhereClient.shared.adminBackup()
            flash("Backed up as \(filename)")
            await reloadActivity()
        }
    }

    func clearCache() async {
        await run {
            try await PythonAnywhereClient.shared.adminClearCache()
            flash("Stats cache cleared")
            await reloadActivity()
        }
    }

    func testEmail() async {
        await run {
            let message = try await PythonAnywhereClient.shared.adminTestEmail()
            flash(message)
            await reloadActivity()
        }
    }

    func addUser() async {
        let username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = newPassword
        guard !username.isEmpty else {
            flash("Username is required", error: true)
            return
        }
        guard password.count >= 8 else {
            flash("Password must be at least 8 characters", error: true)
            return
        }
        await run {
            try await PythonAnywhereClient.shared.adminAddUser(
                username: username,
                password: password,
                isAdmin: newIsAdmin
            )
            newUsername = ""
            newPassword = ""
            newIsAdmin = false
            flash("Created \(username)")
            await loadAll()
        }
    }

    func confirmResetPassword() async {
        let user = resetTarget
        let password = resetPassword
        resetTarget = nil
        resetPassword = ""
        guard let user else { return }
        guard password.count >= 8 else {
            flash("Password must be at least 8 characters", error: true)
            return
        }
        await run {
            try await PythonAnywhereClient.shared.adminResetPassword(username: user.username, password: password)
            flash("Password updated for \(user.username)")
            await reloadActivity()
        }
    }

    func confirmToggle() async {
        let user = pendingToggle
        pendingToggle = nil
        guard let user else { return }
        let activate = !user.isActiveUser
        await run {
            try await PythonAnywhereClient.shared.adminToggleActive(username: user.username, active: activate)
            flash(activate ? "Reactivated \(user.username)" : "Deactivated \(user.username)")
            await loadAll()
        }
    }

    func refreshed(_ entry: AdminActivityEntry) async -> AdminActivityEntry {
        if !entry.resolvedChanges.isEmpty { return entry }
        let isGame = ["doubles_game", "vollis_game", "other_game"].contains(entry.target ?? "")
        guard isGame else { return entry }
        if let full = try? await PythonAnywhereClient.shared.adminActivityEntry(id: entry.id) {
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[i] = full
            }
            return full
        }
        return entry
    }

    func flash(_ text: String, error: Bool = false) {
        banner = text
        bannerIsError = error
        let shown = text
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if banner == shown { banner = nil }
        }
    }

    private func applyActivityPage(_ page: AdminActivityPage, append: Bool) {
        activityPage = page.page
        activityTotal = page.total
        hasMoreActivity = page.hasMore
        if append {
            let existing = Set(entries.map(\.id))
            entries.append(contentsOf: page.entries.filter { !existing.contains($0.id) })
        } else {
            entries = page.entries
        }
    }

    private func run(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await work()
        } catch {
            flash(error.localizedDescription, error: true)
        }
    }
}

struct SiteAdminView: View {
    @StateObject private var model = AdminDashboardModel()
    @ObservedObject private var auth = SiteAuthManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $model.pane) {
                ForEach(AdminPane.allCases) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let banner = model.banner {
                SiteAddBanner(text: banner, isError: model.bannerIsError)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            Group {
                switch model.pane {
                case .overview:
                    AdminOverviewPane(model: model)
                case .activity:
                    AdminActivityPane(model: model)
                case .users:
                    AdminUsersPane(model: model, currentUsername: auth.username)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.loading || model.busy {
                    ProgressView()
                } else {
                    Button {
                        Task { await model.loadAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
        .task { await model.loadAll() }
        .refreshable { await model.loadAll() }
        .confirmationDialog(
            undoTitle,
            isPresented: Binding(
                get: { model.pendingUndo != nil },
                set: { if !$0 { model.pendingUndo = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Undo", role: .destructive) {
                if let entry = model.pendingUndo {
                    Task { await model.undo(entry) }
                }
            }
            Button("Cancel", role: .cancel) { model.pendingUndo = nil }
        } message: {
            Text(undoMessage)
        }
        .confirmationDialog(
            toggleTitle,
            isPresented: Binding(
                get: { model.pendingToggle != nil },
                set: { if !$0 { model.pendingToggle = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(toggleConfirmTitle, role: model.pendingToggle?.isActiveUser == true ? .destructive : nil) {
                Task { await model.confirmToggle() }
            }
            Button("Cancel", role: .cancel) { model.pendingToggle = nil }
        }
        .alert("Reset password", isPresented: Binding(
            get: { model.resetTarget != nil },
            set: { if !$0 { model.resetTarget = nil; model.resetPassword = "" } }
        )) {
            SecureField("New password (8+ characters)", text: $model.resetPassword)
            Button("Reset") { Task { await model.confirmResetPassword() } }
            Button("Cancel", role: .cancel) { model.resetPassword = "" }
        } message: {
            Text("Set a new password for \(model.resetTarget?.username ?? "this user").")
        }
    }

    private var undoTitle: String {
        guard let kind = model.pendingUndo?.undoKind, !kind.isEmpty else { return "Undo this change?" }
        return "Undo this \(kind)?"
    }

    private var undoMessage: String {
        switch model.pendingUndo?.undoKind {
        case "edit": return "The game will be restored to its previous values."
        case "delete": return "The deleted game will be re-created."
        case "add": return "The added game will be removed."
        default: return "This reverses the logged change."
        }
    }

    private var toggleTitle: String {
        guard let user = model.pendingToggle else { return "Update user?" }
        return user.isActiveUser ? "Deactivate \(user.username)?" : "Reactivate \(user.username)?"
    }

    private var toggleConfirmTitle: String {
        model.pendingToggle?.isActiveUser == true ? "Deactivate" : "Reactivate"
    }
}

struct AdminOverviewPane: View {
    @ObservedObject var model: AdminDashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.loading && model.overview == nil {
                    ProgressView("Loading dashboard…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = model.loadError, model.overview == nil {
                    ContentUnavailableView {
                        Label("Couldn’t load admin", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await model.loadAll() } }
                    }
                    .padding(.top, 20)
                } else if let overview = model.overview {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        AdminStatCard(
                            title: "Doubles",
                            value: overview.counts.doubles.today,
                            subtitle: "\(overview.counts.doubles.week) this week · \(overview.counts.doubles.total) total"
                        )
                        AdminStatCard(
                            title: "Vollis",
                            value: overview.counts.vollis.today,
                            subtitle: "\(overview.counts.vollis.week) this week · \(overview.counts.vollis.total) total"
                        )
                        AdminStatCard(
                            title: "Other",
                            value: overview.counts.other.today,
                            subtitle: "\(overview.counts.other.week) this week · \(overview.counts.other.total) total"
                        )
                        AdminStatCard(
                            title: overview.activity == nil ? "Logged actions" : "Actions today",
                            value: overview.activity?.today ?? model.activityTotal,
                            subtitle: dbSubtitle(overview)
                        )
                    }

                    if let game = overview.recentGame, let summary = game.summary, !summary.isEmpty {
                        AdminCard(title: "Latest game") {
                            Text(summary).font(.subheadline)
                            HStack {
                                if let kind = game.kind {
                                    Text(kind.capitalized)
                                }
                                if let date = game.gameDate, !date.isEmpty {
                                    Text(date)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if let actions = overview.activity?.todayByAction, !actions.isEmpty {
                        AdminCard(title: "Today") {
                            ForEach(actions) { row in
                                Button {
                                    model.showActivity(action: row.action)
                                } label: {
                                    HStack {
                                        Text(row.action)
                                        Spacer()
                                        Text("\(row.count)")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(SiteAddAccent.orange)
                                    }
                                    .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    AdminCard(title: "Latest activity") {
                        if model.entries.isEmpty {
                            Text("Nothing logged yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.entries.prefix(8)) { entry in
                                NavigationLink {
                                    AdminActivityDetailView(model: model, seed: entry)
                                } label: {
                                    AdminActivityRow(entry: entry, compact: true)
                                }
                                .buttonStyle(.plain)
                            }
                            Button("See everything (\(model.activityTotal))") {
                                model.pane = .activity
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SiteAddAccent.orange)
                        }
                    }

                    AdminCard(title: "Maintenance") {
                        AdminActionButton(title: "Back up database", systemImage: "externaldrive") {
                            Task { await model.backup() }
                        }
                        AdminActionButton(title: "Clear stats cache", systemImage: "arrow.clockwise") {
                            Task { await model.clearCache() }
                        }
                        AdminActionButton(
                            title: "Send test email",
                            systemImage: "envelope",
                            disabled: !model.emailConfigured
                        ) {
                            Task { await model.testEmail() }
                        }
                        if !model.emailConfigured {
                            Text("Email isn’t configured on the server.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let url = URL(string: "\(SitePublicLink.host)/admin/") {
                        Link(destination: url) {
                            Label("Open website dashboard", systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .disabled(model.busy)
        }
    }

    private func dbSubtitle(_ overview: AdminOverview) -> String {
        let total = overview.activity?.total ?? model.activityTotal
        if let mb = overview.dbSizeMb {
            return "\(total) logged · \(mb.formatted()) MB"
        }
        return "\(total) logged actions"
    }
}

struct AdminActivityPane: View {
    @ObservedObject var model: AdminDashboardModel

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        AdminFilterChip(title: "All", selected: !model.hasActivityFilters) {
                            model.clearActivityFilters()
                        }
                        AdminFilterChip(title: "Games", selected: model.search.lowercased() == "game") {
                            model.setQuickFilter("game")
                        }
                        AdminFilterChip(title: "Logins", selected: model.search.lowercased() == "logged in") {
                            model.setQuickFilter("Logged in")
                        }
                        AdminFilterChip(title: "AI", selected: model.search.uppercased() == "AI") {
                            model.setQuickFilter("AI")
                        }
                        Menu {
                            Button("All users") {
                                model.filterUsername = nil
                                Task { await model.reloadActivity() }
                            }
                            ForEach(model.users) { user in
                                Button(user.username) {
                                    model.showActivity(username: user.username, action: model.actionFilter, search: model.search)
                                }
                            }
                        } label: {
                            AdminFilterChip(
                                title: model.filterUsername ?? "User",
                                selected: model.filterUsername != nil
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                if model.hasActivityFilters {
                    HStack {
                        Text(filterSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { model.clearActivityFilters() }
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            Section {
                if model.entries.isEmpty && !model.loading {
                    Text(model.hasActivityFilters ? "No matching activity." : "Nothing logged yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.entries) { entry in
                    NavigationLink {
                        AdminActivityDetailView(model: model, seed: entry)
                    } label: {
                        AdminActivityRow(entry: entry)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if entry.undoable {
                            Button(entry.undoLabel, role: .destructive) {
                                model.pendingUndo = entry
                            }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("User") { model.showActivity(username: entry.username) }
                            .tint(SiteAddAccent.orange)
                    }
                    .contextMenu {
                        Button("Activity by \(entry.username)") {
                            model.showActivity(username: entry.username)
                        }
                        if entry.undoable {
                            Button(entry.undoLabel, role: .destructive) {
                                model.pendingUndo = entry
                            }
                        }
                    }
                }
                if model.hasMoreActivity {
                    Button {
                        Task { await model.loadMoreActivity() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.loadingMore {
                                ProgressView()
                            } else {
                                Text("Load older activity")
                            }
                            Spacer()
                        }
                    }
                }
            } header: {
                Text(model.activityTotal == 1 ? "1 action" : "\(model.activityTotal) actions")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $model.search, prompt: "Search actions, users, details")
        .onSubmit(of: .search) {
            Task { await model.reloadActivity() }
        }
        .onChange(of: model.search) { _, newValue in
            if newValue.isEmpty && model.actionFilter == nil {
                Task { await model.reloadActivity() }
            }
        }
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let user = model.filterUsername { parts.append(user) }
        if let action = model.actionFilter { parts.append(action) }
        let q = model.search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { parts.append("“\(q)”") }
        return parts.joined(separator: " · ")
    }
}

struct AdminUsersPane: View {
    @ObservedObject var model: AdminDashboardModel
    var currentUsername: String?

    var body: some View {
        List {
            Section("Site users") {
                if model.users.isEmpty && !model.loading {
                    Text("No users found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.users) { user in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(user.username)
                                .font(.headline)
                            if user.isAdminUser {
                                AdminBadge(text: "Admin", color: SiteAddAccent.orange)
                            }
                            if !user.isActiveUser {
                                AdminBadge(text: "Deactivated", color: .red)
                            }
                        }
                        .opacity(user.isActiveUser ? 1 : 0.55)

                        VStack(spacing: 4) {
                            AdminMetaRow(label: "Last login", value: AdminTime.full(user.lastLogin))
                            AdminMetaRow(label: "Last activity", value: AdminTime.full(user.lastSeen))
                        }

                        HStack(spacing: 10) {
                            Button("Activity") {
                                model.showActivity(username: user.username)
                            }
                            Button("Reset password") {
                                model.resetPassword = ""
                                model.resetTarget = user
                            }
                            if user.username.lowercased() != currentUsername?.lowercased() {
                                Button(user.isActiveUser ? "Deactivate" : "Reactivate") {
                                    model.pendingToggle = user
                                }
                                .foregroundStyle(user.isActiveUser ? Color.red : Color.green)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Add user") {
                TextField("Username", text: $model.newUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password (8+ characters)", text: $model.newPassword)
                    .textContentType(.newPassword)
                Toggle("Admin access", isOn: $model.newIsAdmin)
                Button("Create user") {
                    Task { await model.addUser() }
                }
                .disabled(model.busy || model.newUsername.trimmingCharacters(in: .whitespaces).isEmpty || model.newPassword.count < 8)
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct AdminActivityDetailView: View {
    @ObservedObject var model: AdminDashboardModel
    let seed: AdminActivityEntry
    @State private var entry: AdminActivityEntry
    @State private var confirmUndo = false

    init(model: AdminDashboardModel, seed: AdminActivityEntry) {
        self.model = model
        self.seed = seed
        _entry = State(initialValue: seed)
    }

    var body: some View {
        List {
            Section {
                AdminMetaRow(label: "User", value: entry.username)
                AdminMetaRow(label: "Action", value: entry.action)
                AdminMetaRow(label: "When", value: AdminTime.full(entry.createdAt))
                if let target = entry.targetLabel {
                    AdminMetaRow(label: "Target", value: target)
                }
                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                }
                if entry.undone {
                    Text("This change was undone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !entry.resolvedChanges.isEmpty {
                Section("What changed") {
                    ForEach(entry.resolvedChanges) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prettyField(change.field))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let before = change.before, !before.isEmpty {
                                Text(before)
                                    .strikethrough()
                                    .foregroundStyle(.red)
                            }
                            if let after = change.after, !after.isEmpty {
                                Text(after)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            if entry.undoable {
                Section {
                    Button(entry.undoLabel, role: .destructive) {
                        confirmUndo = true
                    }
                }
            }
        }
        .navigationTitle(entry.action.isEmpty ? "Activity" : entry.action)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            entry = await model.refreshed(seed)
        }
        .confirmationDialog(
            entry.undoKind.map { "Undo this \($0)?" } ?? "Undo this change?",
            isPresented: $confirmUndo,
            titleVisibility: .visible
        ) {
            Button("Undo", role: .destructive) {
                Task {
                    await model.undo(entry)
                    if let updated = model.entries.first(where: { $0.id == entry.id }) {
                        entry = updated
                    } else {
                        entry.undone = true
                        entry.undoable = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(undoMessage)
        }
    }

    private var undoMessage: String {
        switch entry.undoKind {
        case "edit": return "The game will be restored to its previous values."
        case "delete": return "The deleted game will be re-created."
        case "add": return "The added game will be removed."
        default: return "This reverses the logged change."
        }
    }

    private func prettyField(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct AdminActivityRow: View {
    var entry: AdminActivityEntry
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SiteAddAccent.orange)
                Text(entry.action)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if entry.undone {
                    Text("undone")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let summary = entry.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 5)
            }
            HStack(spacing: 6) {
                Text(AdminTime.relative(entry.createdAt))
                if let target = entry.targetLabel {
                    Text("·")
                    Text(target)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .opacity(entry.undone ? 0.55 : 1)
        .padding(.vertical, 2)
    }
}

struct AdminStatCard: View {
    var title: String
    var value: Int
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(SiteAddAccent.orange)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct AdminCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct AdminActionButton: View {
    var title: String
    var systemImage: String
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(disabled)
    }
}

struct AdminFilterChip: View {
    var title: String
    var selected: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        let chip = Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? SiteAddAccent.orange.opacity(0.22) : Color(.tertiarySystemFill))
            )
            .foregroundStyle(selected ? SiteAddAccent.orange : Color.primary)

        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
        } else {
            chip
        }
    }
}

struct AdminBadge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

struct AdminMetaRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
