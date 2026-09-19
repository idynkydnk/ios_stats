import SwiftUI
import Combine

final class SiteTheme: ObservableObject {
    static let shared = SiteTheme()
    @Published var colorScheme: ColorScheme? = .dark

    var isDark: Bool { colorScheme != .light }

    func toggle() {
        colorScheme = isDark ? .light : .dark
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
    @State private var selectedYear: String = String(Calendar.current.component(.year, from: Date()))
    @State private var years: [String] = ["All years"]
    @State private var doublesEdit: DoublesGame?
    @State private var vollisEdit: VollisGame?
    @State private var addKind: GameSection = .doubles

    var body: some View {
        TabView(selection: $selectedTab) {
            SiteStatsView(selectedOtherGame: $selectedOtherGame, section: $section, selectedYear: $selectedYear, years: years)
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(0)
            SiteGamesView(selectedOtherGame: $selectedOtherGame, section: $section, selectedYear: $selectedYear, years: years, canEdit: auth.isLoggedIn, onEditDoubles: { doublesEdit = $0; addKind = .doubles; selectedTab = 2 }, onEditVollis: { vollisEdit = $0; addKind = .vollis; selectedTab = 2 })
                .tabItem { Label("Games", systemImage: "list.bullet") }
                .tag(1)
            SiteAddHubView(section: $addKind, doublesEdit: $doublesEdit, vollisEdit: $vollisEdit)
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(2)
            SiteMoreView()
                .tabItem { Label("More", systemImage: "line.3.horizontal") }
                .tag(3)
        }
        .tint(Color(red: 1, green: 0.45, blue: 0.3))
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
                if !queue.items.isEmpty {
                    Text("\(queue.items.count) change(s) waiting to sync")
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.9))
                }
            }
        }
        .task {
            await loadYears()
            await auth.refreshMe()
        }
        .onChange(of: section) { _, _ in
            Task { await loadYears() }
        }
        .onChange(of: network.isConnected) { _, online in
            if online { Task { await queue.flush() } }
        }
        .onChange(of: auth.welcomeMessage) { _, message in
            guard message != nil else { return }
            selectedTab = 0
            Task {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                auth.clearWelcome()
            }
        }
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
                if years.isEmpty { years = ["All years", selectedYear] }
            }
        } catch { }
    }
}

struct SectionYearBar: View {
    @Binding var section: GameSection
    @Binding var selectedYear: String
    var years: [String]
    @Binding var search: String
    var searchPrompt: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Picker("Type", selection: Binding(get: { section == .doubles ? GameSection.doubles : .other }, set: { section = $0 })) {
                    Text("Doubles").tag(GameSection.doubles)
                    Text("Other").tag(GameSection.other)
                }
                .pickerStyle(.segmented)
                Picker("Year", selection: $selectedYear) {
                    ForEach(normalizedYears, id: \.self) { y in
                        Text(y == "All years" ? "All" : y).tag(displayTag(y))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
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
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var normalizedYears: [String] {
        var list = years
        if !list.contains(where: { $0 == selectedYear || ($0 == "All years" && selectedYear == "All") }) {
            list.insert(selectedYear, at: 0)
        }
        return list
    }

    private func displayTag(_ y: String) -> String {
        y == "All years" ? "All years" : y
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
    func body(content: Content) -> some View {
        content
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
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
    }
}

struct SiteSectionBubble: View {
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
            .contentShape(RoundedRectangle(cornerRadius: 24))
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
                                Text(row.name).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                                if showRating {
                                    Text(row.rating.map { String(format: "%.2f", $0) } ?? "—")
                                        .frame(width: 48, alignment: .trailing)
                                }
                                Text("\(row.wins)").frame(width: 30, alignment: .trailing).foregroundStyle(.green)
                                Text("\(row.losses)").frame(width: 30, alignment: .trailing).foregroundStyle(.red)
                                Text(row.winPctDisplay).frame(width: 44, alignment: .trailing)
                                if showPlusMinus {
                                    let pm = row.plusMinus ?? 0
                                    Text(pm > 0 ? "+\(pm)" : "\(pm)")
                                        .foregroundStyle(pm > 0 ? Color.green : pm < 0 ? Color.red : .secondary)
                                        .frame(width: 36, alignment: .trailing)
                                }
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
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .padding(.horizontal, 16).padding(.bottom, 20)
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("#").frame(width: 22, alignment: .leading)
            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
            if showRating { Text("Rating").frame(width: 48, alignment: .trailing) }
            Text("W").frame(width: 30, alignment: .trailing)
            Text("L").frame(width: 30, alignment: .trailing)
            Text("Win%").frame(width: 44, alignment: .trailing)
            if showPlusMinus { Text("+/-").frame(width: 36, alignment: .trailing) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }
}

struct SiteStatsView: View {
    @Binding var selectedOtherGame: String
    @Binding var section: GameSection
    @Binding var selectedYear: String
    var years: [String]
    @State private var doubles: DoublesStatsPayload?
    @State private var vollis: VollisStatsPayload?
    @State private var other: OtherStatsPayload?
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionYearBar(section: $section, selectedYear: $selectedYear, years: years, search: $search, searchPrompt: "Search players...")
                ScrollView {
                    if section != .doubles {
                        OtherGameNavigation(section: $section, selection: $selectedOtherGame)
                    }
                    if loading { ProgressView().padding() }
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
                                    showRating: false,
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
                            RankingTable(title: nil, rows: filter(v.stats), showRating: false, year: v.displayYear, section: .vollis)
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
                                RankingTable(title: card.gameName, rows: filter(card.stats), showRating: false, year: o.displayYear, section: .other)
                                if !card.rareStats.isEmpty {
                                    RankingTable(title: "\(card.gameName ?? "") · rare", rows: filter(card.rareStats), showRating: false, year: o.displayYear, section: .other)
                                }
                            }
                        }
                    }
                }
                .id("\(section.rawValue)-\(selectedYear)-\(search)")
                .background(Color(uiColor: .systemGroupedBackground))
                .refreshable { await load() }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SiteCopyLinkButton(url: SitePublicLink.stats(section: section, year: selectedYear, gameName: selectedOtherGame))
                }
            }
            .task(id: "\(section.rawValue)-\(selectedYear)") { await load() }
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

    private func load() async {
        loading = true
        error = nil
        let year = selectedYear == "All" ? "All years" : selectedYear
        do {
            switch section {
            case .doubles:
                doubles = try await PythonAnywhereClient.shared.doublesStats(year: year)
            case .vollis:
                var payload = try await PythonAnywhereClient.shared.vollisStats(year: year)
                if (payload.todayStats ?? []).isEmpty {
                    let games = (try? await PythonAnywhereClient.shared.vollisGames(year: String(Calendar.current.component(.year, from: Date()))))?.games ?? []
                    let todayGames = games.filter { siteIsToday($0.date) }
                    if !todayGames.isEmpty {
                        payload.todayStats = RankingRow.todayStats(fromVollis: todayGames)
                        payload.todayGameCount = todayGames.count
                    }
                }
                vollis = payload
            case .other:
                var payload = try await PythonAnywhereClient.shared.otherStats(year: year)
                let volleyball = try await PythonAnywhereClient.shared.volleyballStats(year: payload.displayYear)
                payload.gameCards.removeAll { $0.isConsolidated == true }
                payload.gameCards.append(contentsOf: volleyball.gameCards)
                other = payload
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct SiteGamesView: View {
    @Binding var selectedOtherGame: String
    @Binding var section: GameSection
    @Binding var selectedYear: String
    var years: [String]
    var canEdit: Bool
    var onEditDoubles: (DoublesGame) -> Void
    var onEditVollis: (VollisGame) -> Void
    @State private var doubles: [DoublesGame] = []
    @State private var vollis: [VollisGame] = []
    @State private var other: [OtherGame] = []
    @State private var gamesExpanded = true
    @State private var search = ""
    @State private var error: String?
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var successTick = 0
    @State private var openedPlayer: SitePlayerRoute?
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = SiteOfflineQueue.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionYearBar(section: $section, selectedYear: $selectedYear, years: years, search: $search, searchPrompt: "Search")
                if let banner {
                    SiteAddBanner(text: banner, isError: bannerIsError)
                        .padding(.horizontal)
                }
                if let error {
                    SiteAddBanner(text: error, isError: true)
                        .padding(.horizontal)
                }
                List {
                    if section != .doubles {
                        OtherGameNavigation(section: $section, selection: $selectedOtherGame)
                    }
                    Section {
                        SiteSectionBubble(title: "Games", count: visibleGameCount, expanded: $gamesExpanded)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                            .listRowSeparator(.visible)
                        if gamesExpanded {
                            switch section {
                            case .doubles:
                                SiteLimitedRows(filteredDoubles) { g in
                                    DoublesGameRow(game: g, year: selectedYear, section: .doubles)
                                        .listRowSeparator(.visible)
                                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                                        .listRowInsets(EdgeInsets())
                                    .buttonStyle(.borderless)
                                    .swipeActions {
                                        if canEdit {
                                            Button("Edit") { onEditDoubles(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteDoubles(g) } }
                                        }
                                    }
                                    .contextMenu {
                                        if canEdit {
                                            Button("Edit") { onEditDoubles(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteDoubles(g) } }
                                        }
                                    }
                                }
                            case .vollis:
                                SiteLimitedRows(filteredVollis) { g in
                                    VollisGameRow(game: g, year: selectedYear, section: .vollis)
                                        .listRowSeparator(.visible)
                                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                                        .listRowInsets(EdgeInsets())
                                    .buttonStyle(.borderless)
                                    .swipeActions {
                                        if canEdit {
                                            Button("Edit") { onEditVollis(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteVollis(g) } }
                                        }
                                    }
                                    .contextMenu {
                                        if canEdit {
                                            Button("Edit") { onEditVollis(g) }
                                            Button("Delete", role: .destructive) { Task { await deleteVollis(g) } }
                                        }
                                    }
                                }
                            case .other:
                                SiteLimitedRows(filteredOther) { g in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text("\(g.gameName ?? "") · \(g.gameType ?? "")").font(.headline)
                                        SiteGameDateLabel(raw: g.gameDateOnly ?? g.gameDate)
                                        SiteTeamScorePanel(score: g.winnerScore, winner: true) {
                                            SitePlayerNamesLine(names: g.displayWinners, year: selectedYear, section: .other, color: .green)
                                        }
                                        SiteTeamScorePanel(score: g.loserScore, winner: false) {
                                            SitePlayerNamesLine(names: g.displayLosers, year: selectedYear, section: .other, color: .red)
                                        }
                                        if let c = g.comment, !c.isEmpty { Text(c).font(.caption).italic() }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                        .listRowSeparator(.visible)
                                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                                        .listRowInsets(EdgeInsets())
                                    .buttonStyle(.borderless)
                                    .swipeActions {
                                        if canEdit {
                                            Button("Delete", role: .destructive) { Task { await deleteOther(g) } }
                                        }
                                    }
                                    .contextMenu {
                                        if canEdit {
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
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.openSitePlayer, OpenSitePlayerAction { openedPlayer = $0 })
            }
            .navigationDestination(item: $openedPlayer) { route in
                SitePlayerDetailView(name: route.name, year: route.year, section: route.section)
                    .environment(\.openSitePlayer, nil)
            }
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SiteCopyLinkButton(url: SitePublicLink.games(section: section, year: selectedYear, gameName: selectedOtherGame))
                }
            }
            .sensoryFeedback(.success, trigger: successTick)
            .refreshable { await load() }
            .task(id: "\(section.rawValue)-\(selectedYear)") {
                banner = nil
                error = nil
                await load()
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

    private func load() async {
        let year = selectedYear == "All" ? "All years" : selectedYear
        do {
            switch section {
            case .doubles:
                let p = try await PythonAnywhereClient.shared.doublesGames(year: year)
                doubles = p.games
            case .vollis:
                let p = try await PythonAnywhereClient.shared.vollisGames(year: year)
                vollis = p.games
            case .other:
                let p = try await PythonAnywhereClient.shared.otherGames(year: year)
                other = p.games
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func showDeletedBanner(offline: Bool = false) {
        error = nil
        bannerIsError = false
        banner = offline ? "Deleted offline — will sync" : "Game deleted"
        successTick += 1
    }

    private func deleteDoubles(_ g: DoublesGame) async {
        if !network.isConnected {
            queue.enqueue(method: "DELETE", path: "/api/doubles/games/\(g.id)", body: nil)
            doubles.removeAll { $0.id == g.id }
            showDeletedBanner(offline: true)
            return
        }
        do {
            try await PythonAnywhereClient.shared.deleteDoubles(id: g.id)
            showDeletedBanner()
            await load()
        } catch {
            banner = nil
            self.error = error.localizedDescription
        }
    }
    private func deleteVollis(_ g: VollisGame) async {
        do {
            try await PythonAnywhereClient.shared.deleteVollis(id: g.id)
            showDeletedBanner()
            await load()
        } catch {
            banner = nil
            self.error = error.localizedDescription
        }
    }
    private func deleteOther(_ g: OtherGame) async {
        do {
            try await PythonAnywhereClient.shared.deleteOther(id: g.id)
            showDeletedBanner()
            await load()
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
                Text(date, style: .date)
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
            if let by = game.updatedBy, !by.isEmpty {
                Text("by \(by)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 16) }
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
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 16) }
    }
}

struct OtherGameNavigation: View {
    @Binding var section: GameSection
    @Binding var selection: String
    @State private var groups: [String: [String]] = ["Volleyball": ["No jump"]]
    @State private var loadError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            choice("All Other", value: "")
            ForEach(groups.keys.sorted { a, b in
                if a == "Volleyball" { return b != "Volleyball" }
                if b == "Volleyball" { return false }
                return a < b
            }, id: \.self) { category in
                Text(category).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                    if category == "Volleyball" {
                        choice("No jump", value: "No jump")
                        choice("Vollis", value: "Vollis", isVollis: true)
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
                            ForEach((groups[category] ?? []).filter { $0 != "No jump" }.sorted(), id: \.self) { name in
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
        .padding()
        .task { await load() }
    }

    private func load() async {
        do {
            groups = try await PythonAnywhereClient.shared.otherNavigationGroups()
            loadError = false
        } catch { loadError = true }
    }

    private func choice(_ title: String, value: String, isVollis: Bool = false) -> some View {
        let selected = isVollis ? section == .vollis : section == .other && selection == value
        return Button {
            selection = isVollis ? "" : value
            section = isVollis ? .vollis : .other
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
