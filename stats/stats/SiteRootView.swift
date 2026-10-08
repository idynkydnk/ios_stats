import SwiftUI
import Combine

private struct SiteAISummaryQueuedKey: EnvironmentKey {
    static let defaultValue: (Int) -> Void = { _ in }
}

struct SiteBackgroundNotice: Identifiable {
    var id = UUID()
    var text: String
    var detail: String? = nil
    var isBusy = true
    var isError = false
}

private struct SiteBackgroundStatusKey: EnvironmentKey {
    static let defaultValue: (SiteBackgroundNotice) -> Void = { _ in }
}

private struct SiteGameSaveStatusKey: EnvironmentKey {
    static let defaultValue: (SiteSavedGameReceipt) -> Void = { _ in }
}

private struct SiteRecapPresentation: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension EnvironmentValues {
    var backgroundStatus: (SiteBackgroundNotice) -> Void {
        get { self[SiteBackgroundStatusKey.self] }
        set { self[SiteBackgroundStatusKey.self] = newValue }
    }

    var gameSaveStatus: (SiteSavedGameReceipt) -> Void {
        get { self[SiteGameSaveStatusKey.self] }
        set { self[SiteGameSaveStatusKey.self] = newValue }
    }

    var aiSummaryQueued: (Int) -> Void {
        get { self[SiteAISummaryQueuedKey.self] }
        set { self[SiteAISummaryQueuedKey.self] = newValue }
    }
}

struct SiteRootView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @ObservedObject private var theme = SiteTheme.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = SiteOfflineQueue.shared
    @State private var selectedTab = 0
    @State private var section: GameSection = .doubles
    @State private var selectedOtherGame = ""
    @State private var doublesYear: String = String(Calendar.current.component(.year, from: Date()))
    @State private var otherYear = "All years"

    private var selectedYear: Binding<String> {
        Binding(
            get: { section == .doubles ? doublesYear : otherYear },
            set: { if section == .doubles { doublesYear = $0 } else { otherYear = $0 } }
        )
    }
    @State private var years: [String] = ["All years"]
    @State private var doublesEdit: DoublesGame?
    @State private var vollisEdit: VollisGame?
    @State private var addKind: GameSection = .doubles
    @State private var addNavigationID = UUID()
    @State private var backgroundStatuses: [SiteBackgroundNotice] = []
    @State private var dismissedStatuses: Set<UUID> = []
    @State private var recapJobID: Int?
    @State private var recapStatus: String?
    @State private var recapReadyURL: URL?
    @State private var recapToOpen: SiteRecapPresentation?
    @State private var recapIsError = false

    var body: some View {
        VStack(spacing: 0) {
            if !queue.items.isEmpty {
                SiteBackgroundStatusBanner(
                    text: "\(queue.items.count) \(queue.items.count == 1 ? "change" : "changes") waiting to sync",
                    isBusy: network.isConnected)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            recapBanner
            ForEach(backgroundStatuses) { game in
                SiteBackgroundStatusBanner(
                    text: game.text,
                    detail: game.detail,
                    isBusy: game.isBusy,
                    isError: game.isError,
                    onDismiss: {
                        dismissedStatuses.insert(game.id)
                        backgroundStatuses.removeAll { $0.id == game.id }
                    })
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            mainTabs
        }
        .environment(\.backgroundStatus) { notice in
            reportBackgroundStatus(notice)
        }
        .environment(\.gameSaveStatus) { game in
            reportBackgroundStatus(SiteBackgroundNotice(id: game.id,
                text: "\(game.title) · \(game.status)", detail: game.detail,
                isBusy: game.isSaving, isError: game.isError))
        }
        .environment(\.aiSummaryQueued) { jobID in
            recapReadyURL = nil
            recapIsError = false
            recapStatus = "Generating your recap in the background…"
            recapJobID = jobID
            selectedTab = 0
            addNavigationID = UUID()
        }
        .tint(theme.appearance.accent)
        .sheet(item: $recapToOpen) { recap in
            NavigationStack {
                SiteRecapPageView(title: "Recap", url: recap.url)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { recapToOpen = nil }
                        }
                    }
            }
        }
        .task(id: recapJobID) {
            guard let jobID = recapJobID else { return }
            let result = await siteWaitForAIShare(jobId: jobID, recap: true)
            guard !Task.isCancelled, recapJobID == jobID else { return }
            recapJobID = nil
            recapReadyURL = result.pageURL
            recapIsError = result.error != nil
            recapStatus = result.pageURL != nil
                ? "Your recap is ready."
                : result.error ?? "Still generating. Check Recaps in a few minutes."
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if let welcome = auth.welcomeMessage {
                    Text(welcome)
                        .font(.subheadline.weight(.semibold))
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.92))
                        .foregroundStyle(.black)
                }
            }
        }
        .task {
            await auth.refreshMe()
            await loadYears()
        }
        .task(id: "\(auth.sessionReady)-\(auth.playerSuggestionsScope)") {
            guard auth.sessionReady, auth.isLoggedIn else { return }
            _ = try? await PythonAnywhereClient.shared.doublesPlayers()
        }
        .task(id: "\(auth.sessionReady)-\(auth.playerSuggestionsScope)") {
            guard auth.sessionReady, auth.isLoggedIn else { return }
            _ = try? await PythonAnywhereClient.shared.otherGameTypes()
        }
        .onChange(of: section) { _, _ in
            Task { await loadYears() }
        }
        .onChange(of: selectedTab) { _, _ in updatePreview() }
        .onChange(of: auth.showStarterStats) { _, visible in
            updatePreview()
        }
        .onChange(of: auth.statsViewRevision) { _, _ in
            doublesEdit = nil
            vollisEdit = nil
            Task { await loadYears() }
        }
        .onChange(of: auth.isPreviewing) { _, _ in
            doublesEdit = nil
            vollisEdit = nil
            Task { await loadYears() }
            if !auth.isPreviewing && network.isConnected { Task { await queue.flush() } }
        }
        .onChange(of: network.isConnected) { _, online in
            if online { Task { await queue.flush() } }
        }
        .onChange(of: auth.username) { _, _ in
            recapJobID = nil
            recapStatus = nil
            recapReadyURL = nil
            recapToOpen = nil
            backgroundStatuses = []
            dismissedStatuses = []
        }
        .onChange(of: auth.welcomeMessage) { _, message in
            guard message != nil else { return }
            selectedTab = 0
        }
        .task(id: auth.welcomeMessage) {
            guard auth.welcomeMessage != nil else { return }
            do { try await Task.sleep(nanoseconds: 2_400_000_000) }
            catch { return }
            auth.clearWelcome()
        }
    }

    private func reportBackgroundStatus(_ notice: SiteBackgroundNotice) {
        guard !dismissedStatuses.contains(notice.id) else { return }
        if let index = backgroundStatuses.firstIndex(where: { $0.id == notice.id }) {
            backgroundStatuses[index] = notice
        } else {
            backgroundStatuses.removeAll { !$0.isBusy }
            backgroundStatuses.append(notice)
        }
    }

    @ViewBuilder
    private var recapBanner: some View {
        if let recapStatus {
            SiteBackgroundStatusBanner(
                text: recapStatus,
                isBusy: recapJobID != nil,
                isError: recapIsError,
                actionTitle: recapReadyURL == nil ? nil : "Open recap",
                onAction: {
                    if let recapReadyURL { recapToOpen = SiteRecapPresentation(url: recapReadyURL) }
                },
                onDismiss: { self.recapStatus = nil })
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            SiteStatsView(selectedOtherGame: $selectedOtherGame, section: $section, selectedYear: selectedYear, years: years, isActive: selectedTab == 0)
                .id("\(auth.sessionReady)-\(auth.username ?? "signed-out")-\(auth.isLoggedIn)-\(auth.isPreviewing)-\(auth.statsViewRevision)")
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(0)
            SiteGamesView(selectedOtherGame: $selectedOtherGame, section: $section, selectedYear: selectedYear, years: years, isActive: selectedTab == 1, canEdit: auth.isLoggedIn && !auth.isPreviewing, onEditDoubles: { doublesEdit = $0; addKind = .doubles; selectedTab = 2 }, onEditVollis: { vollisEdit = $0; addKind = .vollis; selectedTab = 2 })
                .id("\(auth.sessionReady)-\(auth.username ?? "signed-out")-\(auth.isLoggedIn)-\(auth.isPreviewing)-\(auth.statsViewRevision)")
                .tabItem { Label("Games", systemImage: "list.bullet") }
                .tag(1)
            SiteAddHubView(section: $addKind, doublesEdit: $doublesEdit, vollisEdit: $vollisEdit)
                .id(addNavigationID)
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(2)
            SiteMoreView(onHome: { selectedTab = 0 })
                .tabItem { Label("More", systemImage: "line.3.horizontal") }
                .tag(3)
        }
    }

    private func updatePreview() {
        auth.isPreviewing = !auth.isLoggedIn
        auth.browseSelectedStats = selectedTab != 2
    }

    private func loadYears() async {
        do {
            let y = try await PythonAnywhereClient.shared.years()
            await MainActor.run {
                switch section {
                case .doubles: years = y.doubles
                case .vollis: years = y.vollis
                case .other: years = y.other
                }
                if years.isEmpty { years = ["All years", selectedYear.wrappedValue] }
            }
        } catch { }
    }
}

struct SiteStarterStatsControl: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var confirmHide = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 4) {
            Button { confirmHide = true } label: {
                Label("Hide KT Stats", systemImage: "eye.slash")
            }.disabled(busy)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.bottom, 8)
        .confirmationDialog("Hide KT Stats?", isPresented: $confirmHide, titleVisibility: .visible) {
            Button("Hide KT Stats") {
                Task {
                    busy = true
                    error = nil
                    do { try await auth.setStarterStats(visible: false) }
                    catch { self.error = error.localizedDescription }
                    busy = false
                }
            }
        } message: {
            Text("Only your games and stats will be shown. Nothing is deleted. You can show KT Stats again in More.")
        }
    }
}

struct SiteYearMenu: View {
    @Binding var selectedYear: String
    var years: [String]

    var body: some View {
        Picker("Year", selection: $selectedYear) {
            ForEach(normalizedYears, id: \.self) { year in
                Text(year == "All years" ? "All" : year).tag(year)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Year")
    }

    private var normalizedYears: [String] {
        var list = years
        if !list.contains(where: { $0 == selectedYear || ($0 == "All years" && selectedYear == "All") }) {
            list.insert(selectedYear, at: 0)
        }
        return list
    }
}

struct SiteSearchBar: View {
    @Environment(\.siteAppearance) private var appearance

    @Binding var search: String
    var searchPrompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(searchPrompt, text: $search)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(appearance.panel, in: RoundedRectangle(cornerRadius: appearance.style.radius(16)))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(appearance.background)
    }
}

// Shared disclosure cards keep the same motion and spacing across stats and games.
struct SiteSpringButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.58), value: configuration.isPressed)
    }
}

// One surface encloses both a section heading and its content.
struct SiteCardSurface: ViewModifier {
    @Environment(\.siteAppearance) private var appearance

    func body(content: Content) -> some View {
        content
            .background(appearance.panel)
            .clipShape(RoundedRectangle(cornerRadius: appearance.style.radius(24), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: appearance.style.radius(24), style: .continuous)
                .strokeBorder(appearance.style == .sharp ? appearance.accent.opacity(0.5) : Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(appearance.style == .soft ? 0.12 : 0), radius: 10, y: 4)
    }
}

struct SiteCardHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SiteContentCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SiteCardHeading(title: title)
            Divider().padding(.horizontal, 18)
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .modifier(SiteCardSurface())
    }
}

// Keep native list rows (and their swipe actions) inside the heading's group.
struct SiteListSection<Content: View>: View {
    @Environment(\.siteAppearance) private var appearance

    var title: String
    var content: Content
    var footer: AnyView = AnyView(EmptyView())

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init<Footer: View>(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = AnyView(footer())
    }

    var body: some View {
        Section {
            SiteCardHeading(title: title)
                .listRowInsets(EdgeInsets())
            content
        } footer: {
            footer
        }
        .listRowBackground(appearance.panel)
    }
}

struct SiteSectionBubble: View {
    @Environment(\.siteAppearance) private var appearance

    var title: String
    var count: Int
    var subtitle: String? = nil
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline.weight(.bold))
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(count.formatted())
                    .font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentColor.opacity(expanded ? 0.12 : 0.22), in: Capsule())
                    .scaleEffect(reduceMotion ? 1 : (expanded ? 1 : 1.1))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(.primary)
            .padding(18)
            .frame(minHeight: 64)
            .contentShape(RoundedRectangle(cornerRadius: appearance.style.radius(24)))
        }
        .buttonStyle(SiteSpringButtonStyle())
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(expanded ? "collapse" : "expand") \(title)")
    }
}


// Reuse the same preview length and controls in cards and native Lists.
// Keep rows as direct children so navigation and swipe actions stay native.
struct SiteLimitedRows<Element, ID: Hashable, Row: View>: View {
    private let items: [Element]
    private let id: KeyPath<Element, ID>
    private let onDelete: ((IndexSet) -> Void)?
    private let row: (Element) -> Row
    @State private var extended = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let previewCount = 25

    init<C: Collection>(_ items: C, id: KeyPath<Element, ID>,
                        onDelete: ((IndexSet) -> Void)? = nil,
                        @ViewBuilder content: @escaping (Element) -> Row) where C.Element == Element {
        self.items = Array(items)
        self.id = id
        self.onDelete = onDelete
        self.row = content
    }

    init<C: Collection>(_ items: C, onDelete: ((IndexSet) -> Void)? = nil,
                        @ViewBuilder content: @escaping (Element) -> Row)
    where C.Element == Element, Element: Identifiable, ID == Element.ID {
        self.init(items, id: \.id, onDelete: onDelete, content: content)
    }

    var body: some View {
        Group {
            ForEach(extended ? items : Array(items.prefix(previewCount)), id: id, content: row)
                .onDelete(perform: onDelete)
            if items.count > previewCount {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        extended.toggle()
                    }
                } label: {
                    HStack {
                        Text(extended ? "Show less" : "Extend")
                        Spacer(minLength: 8)
                        Text(extended ? "" : "+\(items.count - previewCount)")
                            .monospacedDigit()
                        Image(systemName: extended ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(extended ? "All \(items.count) items shown" : "\(previewCount) of \(items.count) items shown")
                .accessibilityHint(extended ? "Show the first \(previewCount) items" : "Reveal the remaining items")
            }
        }
        .onChange(of: items.map { $0[keyPath: id] }) { _, _ in extended = false }
    }
}

struct SiteExpandableSection<Content: View>: View {
    var title: String
    var count: Int
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            SiteSectionBubble(title: title, count: count, subtitle: subtitle, expanded: $expanded)
            if expanded {
                Divider().padding(.horizontal, 18)
                VStack(spacing: 0) { content }.transition(.opacity)
            }
        }
        .modifier(SiteCardSurface())
    }
}

struct RankingTable: View {
    @Environment(\.siteAppearance) private var appearance
    @ScaledMetric(relativeTo: .subheadline) private var recordDigitWidth: CGFloat = 10

    var title: String?
    var subtitle: String? = nil
    var rows: [RankingRow]
    var showRating: Bool
    var showPlusMinus: Bool = false
    var sortLikeToday: Bool = false
    var year: String
    var section: GameSection

    private var displayedRows: [RankingRow] {
        sortLikeToday ? RankingRow.sortedForToday(rows) : rows
    }

    // Keep each column wide enough for the full table, including hidden rows.
    private var winsColumnWidth: CGFloat {
        recordColumnWidth(rows.map(\.wins))
    }

    private var lossesColumnWidth: CGFloat {
        recordColumnWidth(rows.map(\.losses))
    }

    private func recordColumnWidth(_ counts: [Int]) -> CGFloat {
        let digits = counts.map { String($0).count }.max() ?? 1
        return max(24, CGFloat(digits) * recordDigitWidth + 2)
    }

    var body: some View {
        SiteExpandableSection(title: title ?? "Standings", count: displayedRows.count, subtitle: subtitle) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerRow.padding(.vertical, 13)
                    SiteLimitedRows(Array(displayedRows.enumerated()), id: \.element.id) { idx, row in
                        NavigationLink {
                            SitePlayerDetailView(name: row.name, year: year, section: section)
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(idx + 1)").frame(width: 22, alignment: .leading).foregroundStyle(.secondary)
                                Text(row.name)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                statCells(row)
                            }
                            .font(.subheadline).monospacedDigit()
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10).padding(.vertical, 12)
                            .frame(minHeight: 50)
                            .background(Color.primary.opacity(idx.isMultiple(of: 2) ? 0.025 : 0.055))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if displayedRows.isEmpty {
                        Text("No players to show").font(.subheadline).foregroundStyle(.secondary).padding(24)
                    }
                }
                .containerRelativeFrame(.horizontal)
            }
            .background(appearance.panel)
        }
        .padding(.horizontal, 8).padding(.bottom, 20)
    }

    @ViewBuilder
    private func statCells(_ row: RankingRow) -> some View {
        if showRating {
            Text(row.rating.map { String(format: "%.2f", $0) } ?? "—")
                .accessibilityLabel(row.rating.map { String(format: "Rating %.2f", $0) } ?? "Unrated")
                .frame(width: 64, alignment: .trailing)
        }
        HStack(spacing: 2) {
            Text("\(row.wins)")
                .lineLimit(1)
                .frame(width: winsColumnWidth, alignment: .trailing)
                .foregroundStyle(.green)
            Text("\(row.losses)")
                .lineLimit(1)
                .frame(width: lossesColumnWidth, alignment: .trailing)
                .foregroundStyle(.red)
        }
        Text(row.winPctDisplay).frame(width: 44, alignment: .trailing)
        if showPlusMinus {
            let pm = row.plusMinus ?? 0
            Text(pm > 0 ? "+\(pm)" : "\(pm)")
                .foregroundStyle(pm > 0 ? Color.green : pm < 0 ? Color.red : .secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("#").frame(width: 22, alignment: .leading)
            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
            statHeaders
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var statHeaders: some View {
        if showRating { Text("Rating").frame(width: 64, alignment: .trailing) }
        HStack(spacing: 2) {
            Text("W").frame(width: winsColumnWidth, alignment: .trailing)
            Text("L").frame(width: lossesColumnWidth, alignment: .trailing)
        }
        Text("Win%").frame(width: 44, alignment: .trailing)
        if showPlusMinus { Text("+/-").frame(width: 36, alignment: .trailing) }
    }

}

struct SiteStatsView: View {
    @Environment(\.siteAppearance) private var appearance

    @Binding var selectedOtherGame: String
    @Binding var section: GameSection
    @Binding var selectedYear: String
    var years: [String]
    var isActive: Bool
    @State private var dataRevision = UUID()
    @AppStorage("stats.doublesDivision") private var division = "open"
    @State private var doubles: DoublesStatsPayload?
    @State private var vollis: VollisStatsPayload?
    @State private var other: OtherStatsPayload?
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var loadID = UUID()
    @State private var displayedCacheKey: String?

    private struct Snapshot: Codable {
        var doubles: DoublesStatsPayload?
        var vollis: VollisStatsPayload?
        var other: OtherStatsPayload?
    }

    private var cacheKey: String { "\(auth.browseCacheScope)-stats-\(section.rawValue)-\(selectedYear)-\(division)" }
    private var hasStats: Bool {
        switch section {
        case .doubles: return doubles != nil
        case .vollis: return vollis != nil
        case .other: return other != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SiteSearchBar(search: $search, searchPrompt: "Search players...")
                ScrollView {
                    OtherGameNavigation(section: $section, selection: $selectedOtherGame, selectedYear: $selectedYear)
                    if let error { Text(error).foregroundStyle(.red).padding() }
                    switch section {
                    case .doubles:
                        if let d = doubles {
                            if d.showingPreviousYear {
                                Text("No games yet this year. Showing \(d.displayYear).")
                                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                            }
                            if !d.todayStats.isEmpty {
                                RankingTable(
                                    title: "Today's Stats",
                                    subtitle: gameCountLabel(d.todayGameCount),
                                    rows: filter(d.todayStats),
                                    showRating: true,
                                    showPlusMinus: true,
                                    sortLikeToday: true,
                                    year: d.displayYear,
                                    section: .doubles
                                )
                            }
                            RankingTable(title: "Standings", rows: filter(d.stats), showRating: true, year: d.displayYear, section: .doubles)
                            if !d.rareStats.isEmpty {
                                RankingTable(title: "Fewer than \(d.minimumGames) games", rows: filter(d.rareStats), showRating: true, year: d.displayYear, section: .doubles)
                            }
                        }
                    case .vollis:
                        if let v = vollis {
                            if v.showingPreviousYear {
                                Text("No games yet this year. Showing \(v.displayYear).")
                                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                            }
                            if let today = v.todayStats, !today.isEmpty {
                                RankingTable(
                                    title: "Today's Stats",
                                    subtitle: gameCountLabel(v.todayGameCount ?? today.count),
                                    rows: filter(today),
                                    showRating: false,
                                    showPlusMinus: true,
                                    sortLikeToday: true,
                                    year: v.displayYear,
                                    section: .vollis
                                )
                            }
                            RankingTable(title: nil, rows: filter(v.stats), showRating: v.stats.contains { $0.rating != nil }, year: v.displayYear, section: .vollis)
                        }
                    case .other:
                        if let o = other {
                            if o.showingPreviousYear {
                                Text("No games yet this year. Showing \(o.displayYear).")
                                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                            }
                            SiteLimitedRows(o.todayStatsByGame.filter { selectedOtherGame.isEmpty || $0.gameName == selectedOtherGame }) { block in
                                let count = block.gameCount ?? block.stats.count
                                RankingTable(
                                    title: "Today's \(block.gameName ?? "Other")",
                                    subtitle: gameCountLabel(count),
                                    rows: filter(block.stats),
                                    showRating: false,
                                    showPlusMinus: true,
                                    sortLikeToday: true,
                                    year: o.displayYear,
                                    section: .other
                                )
                            }
                            if !selectedOtherGame.isEmpty && !o.gameCards.contains(where: { $0.gameName == selectedOtherGame }) {
                                Text("No \(selectedOtherGame) games in \(o.displayYear). Try All years.")
                                    .foregroundStyle(.secondary).padding()
                            }
                            SiteLimitedRows(o.gameCards.filter { selectedOtherGame.isEmpty || $0.gameName == selectedOtherGame }) { card in
                                RankingTable(title: card.gameName, subtitle: card.ratingEnabled == true ? "Skill rating · \(card.ratedGames ?? 0) rated · \(card.unratedGames ?? 0) excluded" : nil, rows: filter(card.stats), showRating: card.ratingEnabled == true, year: o.displayYear, section: .other)
                                if !card.rareStats.isEmpty {
                                    RankingTable(title: "\(card.gameName ?? "") · rare", rows: filter(card.rareStats), showRating: card.ratingEnabled == true, year: o.displayYear, section: .other)
                                }
                            }
                        }
                    }
                }
                .id("\(section.rawValue)-\(selectedYear)-\(search)")
                .background(appearance.background)
                .refreshable { await load(force: true) }
            }
            .navigationTitle(loading ? (hasStats ? "Updating stats…" : "Loading stats…") : "Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SiteYearMenu(selectedYear: $selectedYear, years: years)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SiteCopyLinkButton(url: SitePublicLink.stats(section: section, year: selectedYear, gameName: selectedOtherGame))
                }
            }
            .task(id: "\(cacheKey)-\(isActive)-\(dataRevision)") {
                guard isActive else { return }
                await load()
            }
            .onReceive(NotificationCenter.default.publisher(for: SiteBrowseCache.didChange, object: SiteBrowseCache.shared)
                .receive(on: RunLoop.main)) { _ in
                dataRevision = UUID()
            }
        }
    }

    private func filter(_ rows: [RankingRow]) -> [RankingRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return rows }
        return rows.filter { $0.name.lowercased().contains(q) }
    }

    private func gameCountLabel(_ n: Int) -> String {
        n == 1 ? "1 game" : "\(n) games"
    }

    @MainActor
    private func load(force: Bool = false) async {
        guard auth.sessionReady else { return }
        let requestID = UUID()
        loadID = requestID
        let key = cacheKey
        let scope = auth.browseCacheScope
        let cache = SiteBrowseCache.shared
        let generation = cache.generation
        let cached = cache.load(Snapshot.self, key: key)
        if let cached, displayedCacheKey != key {
            doubles = cached.value.doubles
            vollis = cached.value.vollis
            other = cached.value.other
        } else if displayedCacheKey != key {
            doubles = nil
            vollis = nil
            other = nil
        }
        displayedCacheKey = key
        loading = false
        error = nil
        if !force, cached?.isFresh() == true { return }
        loading = true
        defer { if loadID == requestID { loading = false } }
        error = nil
        let year = selectedYear == "All" ? "All years" : selectedYear
        do {
            switch section {
            case .doubles:
                let payload = try await PythonAnywhereClient.shared.doublesStats(year: year)
                try Task.checkCancellation()
                guard loadID == requestID, auth.browseCacheScope == scope, cache.generation == generation else { return }
                doubles = payload
                if payload.showingPreviousYear { selectedYear = payload.displayYear }
            case .vollis:
                var payload = try await PythonAnywhereClient.shared.vollisStats(year: year)
                if payload.todayStats == nil {
                    let games = (try? await PythonAnywhereClient.shared.vollisGames(year: String(Calendar.current.component(.year, from: Date()))))?.games ?? []
                    let todayGames = games.filter { siteIsToday($0.date) }
                    if !todayGames.isEmpty {
                        payload.todayStats = RankingRow.todayStats(fromVollis: todayGames)
                        payload.todayGameCount = todayGames.count
                    }
                }
                try Task.checkCancellation()
                guard loadID == requestID, auth.browseCacheScope == scope, cache.generation == generation else { return }
                vollis = payload
                if payload.showingPreviousYear { selectedYear = payload.displayYear }
            case .other:
                async let otherRequest = PythonAnywhereClient.shared.otherStats(year: year)
                async let volleyballRequest = PythonAnywhereClient.shared.volleyballStats(year: year)
                var payload = try await otherRequest
                var volleyball = try await volleyballRequest
                if payload.displayYear != year {
                    volleyball = try await PythonAnywhereClient.shared.volleyballStats(year: payload.displayYear)
                }
                payload.gameCards.removeAll { $0.isConsolidated == true }
                payload.gameCards.append(contentsOf: volleyball.gameCards)
                try Task.checkCancellation()
                guard loadID == requestID, auth.browseCacheScope == scope, cache.generation == generation else { return }
                other = payload
                if payload.showingPreviousYear { selectedYear = payload.displayYear }
            }
            cache.save(Snapshot(doubles: doubles, vollis: vollis, other: other), key: key, generation: generation)
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            self.error = hasStats ? "Showing saved stats. " + error.localizedDescription : error.localizedDescription
        }
    }
}

struct SiteGamesView: View {
    @Environment(\.siteAppearance) private var appearance

    @Binding var selectedOtherGame: String
    @Binding var section: GameSection
    @Binding var selectedYear: String
    var years: [String]
    var isActive: Bool
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var dataRevision = UUID()
    var canEdit: Bool
    var onEditDoubles: (DoublesGame) -> Void
    var onEditVollis: (VollisGame) -> Void
    @State private var doubles: [DoublesGame] = []
    @State private var vollis: [VollisGame] = []
    @State private var other: [OtherGame] = []
    @AppStorage("stats.doublesDivision") private var division = "open"
    @State private var gamesExpanded = true
    @State private var search = ""
    @State private var error: String?
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var isDeleting = false
    @State private var successTick = 0
    @State private var openedPlayer: SitePlayerRoute?
    @State private var loadID = UUID()
    @State private var displayedCacheKey: String?
    private struct Snapshot: Codable {
        var doubles: [DoublesGame]
        var vollis: [VollisGame]
        var other: [OtherGame]
    }
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = SiteOfflineQueue.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SiteSearchBar(search: $search, searchPrompt: "Search")
                if isDeleting && banner == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Deleting game…")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(12)
                    .background(appearance.panel, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .accessibilityElement(children: .combine)
                }
                if let banner {
                    SiteAddBanner(text: banner, isError: bannerIsError)
                        .padding(.horizontal)
                }
                if let error {
                    SiteAddBanner(text: error, isError: true)
                        .padding(.horizontal)
                }
                List {
                    OtherGameNavigation(section: $section, selection: $selectedOtherGame, selectedYear: $selectedYear)
                    Section {
                        SiteSectionBubble(title: "Games", count: visibleGameCount, expanded: $gamesExpanded)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(appearance.panel)
                            .listRowSeparator(.hidden)
                        if gamesExpanded {
                            switch section {
                            case .doubles:
                                SiteLimitedRows(filteredDoubles) { g in
                                    DoublesGameRow(game: g, year: selectedYear, section: .doubles)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(appearance.panel)
                                        .listRowInsets(EdgeInsets())
                                    .buttonStyle(.borderless)
                                    .swipeActions {
                                        if canEdit && g.id < 4_294_967_296 && !isDeleting {
                                            Button("Edit") { onEditDoubles(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteDoubles(g) } }
                                        }
                                    }
                                    .contextMenu {
                                        if canEdit && g.id < 4_294_967_296 && !isDeleting {
                                            Button("Edit") { onEditDoubles(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteDoubles(g) } }
                                        }
                                    }
                                }
                            case .vollis:
                                SiteLimitedRows(filteredVollis) { g in
                                    VollisGameRow(game: g, year: selectedYear, section: .vollis)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(appearance.panel)
                                        .listRowInsets(EdgeInsets())
                                    .buttonStyle(.borderless)
                                    .swipeActions {
                                        if canEdit && g.id < 4_294_967_296 && !isDeleting {
                                            Button("Edit") { onEditVollis(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteVollis(g) } }
                                        }
                                    }
                                    .contextMenu {
                                        if canEdit && g.id < 4_294_967_296 && !isDeleting {
                                            Button("Edit") { onEditVollis(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteVollis(g) } }
                                        }
                                    }
                                }
                            case .other:
                                SiteLimitedRows(filteredOther) { g in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text("\(g.gameName ?? "") · \(g.gameType ?? "")").font(.headline)
                                        SiteGameDateLabel(raw: g.gameDate ?? g.gameDateOnly)
                                        SiteTeamScorePanel(score: g.winnerScore, winner: true) {
                                            SitePlayerNamesLine(names: g.displayWinners, year: selectedYear, section: .other, color: .green)
                                        }
                                        SiteTeamScorePanel(score: g.loserScore, winner: false) {
                                            SitePlayerNamesLine(names: g.displayLosers, year: selectedYear, section: .other, color: .red)
                                        }
                                        if let c = g.comment, !c.isEmpty { Text(c).font(.caption).italic() }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(appearance.panel)
                                        .listRowInsets(EdgeInsets())
                                    .buttonStyle(.borderless)
                                    .swipeActions {
                                        if canEdit && g.id < 4_294_967_296 && !isDeleting {
                                            Button("Delete", role: .destructive) { Task { await deleteOther(g) } }
                                        }
                                    }
                                    .contextMenu {
                                        if canEdit && g.id < 4_294_967_296 && !isDeleting {
                                            Button("Delete", role: .destructive) { Task { await deleteOther(g) } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .id("\(section.rawValue)-\(selectedYear)-\(search)")
                .listStyle(.insetGrouped)
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(appearance.background)
                .environment(\.openSitePlayer, OpenSitePlayerAction { openedPlayer = $0 })
            }
            .navigationDestination(item: $openedPlayer) { route in
                SitePlayerDetailView(name: route.name, year: route.year, section: route.section)
                    .environment(\.openSitePlayer, nil)
            }
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SiteYearMenu(selectedYear: $selectedYear, years: years)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SiteCopyLinkButton(url: SitePublicLink.games(section: section, year: selectedYear, gameName: selectedOtherGame))
                }
            }
            .sensoryFeedback(.success, trigger: successTick)
            .refreshable { await load(force: true) }
            .task(id: "\(auth.browseCacheScope)-\(section.rawValue)-\(selectedYear)-\(division)-\(isActive)-\(dataRevision)") {
                guard isActive else { return }
                error = nil
                await load()
            }
            .onReceive(NotificationCenter.default.publisher(for: SiteBrowseCache.didChange, object: SiteBrowseCache.shared)
                .receive(on: RunLoop.main)) { _ in
                dataRevision = UUID()
            }
        }
    }

    private var visibleGameCount: Int {
        switch section {
        case .doubles: return filteredDoubles.count
        case .vollis: return filteredVollis.count
        case .other: return filteredOther.count
        }
    }

    private var filteredDoubles: [DoublesGame] {
        let q = search.lowercased()
        return doubles.filter {
            q.isEmpty || [$0.winner1, $0.winner2, $0.loser1, $0.loser2, $0.comments].compactMap { $0 }.joined(separator: " ").lowercased().contains(q)
        }
    }
    private var filteredVollis: [VollisGame] {
        let q = search.lowercased()
        return vollis.filter { q.isEmpty || "\($0.winner ?? "") \($0.loser ?? "")".lowercased().contains(q) }
    }
    private var filteredOther: [OtherGame] {
        let q = search.lowercased()
        return other.filter { (selectedOtherGame.isEmpty || $0.gameName == selectedOtherGame) && (q.isEmpty || "\($0.gameName ?? "") \($0.displayWinners) \($0.displayLosers)".lowercased().contains(q)) }
    }

    @MainActor
    private func load(force: Bool = false) async {
        let auth = SiteAuthManager.shared
        guard auth.sessionReady else { return }
        let requestID = UUID()
        loadID = requestID
        let scope = auth.browseCacheScope
        let year = selectedYear == "All" ? "All years" : selectedYear
        let key = "\(scope)-games-\(section.rawValue)-\(year)-\(division)"
        let cache = SiteBrowseCache.shared
        let generation = cache.generation
        let cached = cache.load(Snapshot.self, key: key)
        if displayedCacheKey != key { banner = nil }
        if let cached, displayedCacheKey != key {
            doubles = cached.value.doubles
            vollis = cached.value.vollis
            other = cached.value.other
        } else if displayedCacheKey != key {
            doubles = []
            vollis = []
            other = []
        }
        displayedCacheKey = key
        error = nil
        if !force, cached?.isFresh() == true { return }
        do {
            switch section {
            case .doubles:
                let p = try await PythonAnywhereClient.shared.doublesGames(year: year)
                try Task.checkCancellation()
                guard loadID == requestID, auth.browseCacheScope == scope, cache.generation == generation else { return }
                doubles = p.games
            case .vollis:
                let p = try await PythonAnywhereClient.shared.vollisGames(year: year)
                try Task.checkCancellation()
                guard loadID == requestID, auth.browseCacheScope == scope, cache.generation == generation else { return }
                vollis = p.games
            case .other:
                let p = try await PythonAnywhereClient.shared.otherGames(year: year)
                try Task.checkCancellation()
                guard loadID == requestID, auth.browseCacheScope == scope, cache.generation == generation else { return }
                other = p.games
            }
            cache.save(Snapshot(doubles: doubles, vollis: vollis, other: other), key: key, generation: generation)
            error = nil
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            self.error = (cached == nil ? "" : "Showing saved games. ") + error.localizedDescription
        }
    }

    private func showDeletedBanner(offline: Bool = false) {
        error = nil
        bannerIsError = false
        banner = offline ? "Deleted offline — will sync" : "Game deleted"
        successTick += 1
    }

    @MainActor
    private func deleteDoubles(_ g: DoublesGame) async {
        guard !isDeleting else { return }
        isDeleting = true
        banner = nil
        error = nil
        defer { isDeleting = false }
        if !network.isConnected {
            queue.enqueue(method: "DELETE", path: "/api/doubles/games/\(g.id)", body: nil)
            doubles.removeAll { $0.id == g.id }
            showDeletedBanner(offline: true)
            return
        }
        do {
            try await PythonAnywhereClient.shared.deleteDoubles(id: g.id)
            doubles.removeAll { $0.id == g.id }
            showDeletedBanner()
        } catch {
            banner = nil
            self.error = error.localizedDescription
        }
    }
    @MainActor
    private func deleteVollis(_ g: VollisGame) async {
        guard !isDeleting else { return }
        isDeleting = true
        banner = nil
        error = nil
        defer { isDeleting = false }
        do {
            try await PythonAnywhereClient.shared.deleteVollis(id: g.id)
            vollis.removeAll { $0.id == g.id }
            showDeletedBanner()
        } catch {
            banner = nil
            self.error = error.localizedDescription
        }
    }
    @MainActor
    private func deleteOther(_ g: OtherGame) async {
        guard !isDeleting else { return }
        isDeleting = true
        banner = nil
        error = nil
        defer { isDeleting = false }
        do {
            try await PythonAnywhereClient.shared.deleteOther(id: g.id)
            other.removeAll { $0.id == g.id }
            showDeletedBanner()
        } catch {
            banner = nil
            self.error = error.localizedDescription
        }
    }
}

struct OpenSitePlayerAction {
    var handler: (SitePlayerRoute) -> Void
    func callAsFunction(_ route: SitePlayerRoute) { handler(route) }
}

private struct OpenSitePlayerKey: EnvironmentKey {
    static let defaultValue: OpenSitePlayerAction? = nil
}

extension EnvironmentValues {
    var openSitePlayer: OpenSitePlayerAction? {
        get { self[OpenSitePlayerKey.self] }
        set { self[OpenSitePlayerKey.self] = newValue }
    }
}

struct SitePlayerNameLink: View {
    var name: String
    var year: String?
    var section: GameSection
    var color: Color
    @Environment(\.openSitePlayer) private var openSitePlayer

    var body: some View {
        if let year {
            if let open = openSitePlayer {
                Button {
                    open(SitePlayerRoute(name: name, year: year, section: section))
                } label: {
                    Text(name).foregroundStyle(color)
                }
                .buttonStyle(.borderless)
            } else {
                NavigationLink {
                    SitePlayerDetailView(name: name, year: year, section: section)
                } label: {
                    Text(name).foregroundStyle(color)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text(name).foregroundStyle(color)
        }
    }
}

struct SitePlayerNamesLine: View {
    var names: [String]
    var year: String
    var section: GameSection
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                SitePlayerNameLink(name: name, year: year, section: section, color: color)
            }
        }
    }
}

struct SiteGameDateLabel: View {
    var raw: String?

    var body: some View {
        Group {
            if let date = DoublesGame.parseDate(raw) {
                if raw?.contains(":") == true {
                    Text(date.formatted(.dateTime.month(.wide).day().year().hour().minute()))
                } else {
                    Text(date, style: .date)
                }
            } else if let raw, !raw.isEmpty {
                Text(raw)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct SiteTeamScorePanel<Players: View>: View {
    var score: Int?
    var winner: Bool
    @ViewBuilder var players: Players

    private var color: Color { winner ? .green : .red }
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(winner ? "WINNERS" : "LOSERS")
                    .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                players.font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(score.map(String.init) ?? "—")
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit().foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            Capsule().fill(color).frame(width: 3).padding(.vertical, 10)
        }
    }
}

struct DoublesGameRow: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    var game: DoublesGame
    var year: String? = nil
    var section: GameSection = .doubles
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SiteGameDateLabel(raw: game.gameDate)
            SiteTeamScorePanel(score: game.winnerScore, winner: true) {
                playerPair(game.winner1, game.winner2, color: .green)
            }
            SiteTeamScorePanel(score: game.loserScore, winner: false) {
                playerPair(game.loser1, game.loser2, color: .red)
            }
            if !game.comment.isEmpty { Text(game.comment).font(.caption).foregroundStyle(.secondary) }
            if let by = game.authorDisplayName(currentUsername: auth.username, currentDisplayName: auth.displayName) {
                Text("by \(by)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playerPair(_ a: String?, _ b: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let a, !a.isEmpty { SitePlayerNameLink(name: a, year: year, section: section, color: color) }
            if let b, !b.isEmpty { SitePlayerNameLink(name: b, year: year, section: section, color: color) }
        }
    }
}

struct VollisGameRow: View {
    var game: VollisGame
    var year: String? = nil
    var section: GameSection = .vollis
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SiteGameDateLabel(raw: game.gameDate)
            SiteTeamScorePanel(score: game.winnerScore, winner: true) {
                if let name = game.winner { SitePlayerNameLink(name: name, year: year, section: section, color: .green) }
            }
            SiteTeamScorePanel(score: game.loserScore, winner: false) {
                if let name = game.loser { SitePlayerNameLink(name: name, year: year, section: section, color: .red) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OtherGameNavigation: View {
    @Environment(\.siteAppearance) private var appearance

    @Binding var section: GameSection
    @Binding var selection: String
    @Binding var selectedYear: String
    @AppStorage("stats.doublesDivision") private var division = "open"
    @State private var defaultYears: [String: String] = [:]
    @State private var vollisDefaultYear = "All years"
    @State private var groups: [String: [String]] = ["Volleyball": ["No jump"]]
    @State private var loadError = false
    @State private var expanded = false

    private var selectedGame: String {
        section == .doubles ? "Doubles" : section == .vollis ? "Vollis" : selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                if section == .doubles {
                    divisionChoice("Men’s", value: "open")
                    divisionChoice("Women’s", value: "women")
                } else {
                    Text(selectedGame.isEmpty ? "Choose a game" : selectedGame)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Browse games")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.font(.caption)
                }
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            }
            if expanded { gameChoices.padding(.top, 12) }
        }
        .padding()
        .onAppear { expanded = selectedGame.isEmpty }
        .onChange(of: selectedGame) { _, game in expanded = game.isEmpty }
        .task { await load() }
    }

    private var gameChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups.keys.sorted { a, b in
                if a == "Volleyball" { return b != "Volleyball" }
                if b == "Volleyball" { return false }
                return a < b
            }, id: \.self) { category in
                Text(category).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                    if category == "Volleyball" {
                        choice("Doubles", value: "", destination: .doubles)
                        choice("Vollis", value: "", destination: .vollis)
                        choice("No jump", value: "No jump")
                        if !selection.isEmpty && selection != "No jump" && (groups[category] ?? []).contains(selection) {
                            choice(selection, value: selection)
                        }
                    } else {
                        ForEach((groups[category] ?? []).sorted(), id: \.self) { name in
                            choice(name, value: name)
                        }
                    }
                }
                if category == "Volleyball" {
                    DisclosureGroup("More volleyball games") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                            ForEach((groups[category] ?? []).filter { $0 != "No jump" && $0 != selection }.sorted(), id: \.self) { name in
                                choice(name, value: name)
                            }
                        }.padding(.top, 8)
                    }
                }
            }
            if loadError {
                Button("Retry loading game choices") { Task { await load() } }
            }
        }
    }

    private func load() async {
        do {
            let navigation = try await PythonAnywhereClient.shared.otherNavigationGroups()
            groups = navigation.groups
            defaultYears = navigation.defaultYears
            vollisDefaultYear = navigation.vollisDefaultYear
            loadError = false
        } catch { loadError = true }
    }

    private func divisionChoice(_ title: String, value: String) -> some View {
        Button { division = value } label: {
            Text(title)
                .font(.subheadline.weight(division == value ? .semibold : .regular))
                .foregroundStyle(division == value ? Color.primary : .secondary)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    if division == value { Rectangle().frame(height: 2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(division == value ? .isSelected : [])
    }

    private func choice(_ title: String, value: String, destination: GameSection = .other) -> some View {
        let selected = section == destination && (destination != .other || selection == value)
        return Button {
            selection = destination == .other ? value : ""
            section = destination
            switch destination {
            case .doubles: selectedYear = String(Calendar.current.component(.year, from: Date()))
            case .vollis: selectedYear = vollisDefaultYear
            case .other: selectedYear = defaultYears[value] ?? "All years"
            }
            expanded = false
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.accentColor.opacity(0.18) : appearance.panel, in: RoundedRectangle(cornerRadius: appearance.style.radius(10)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
