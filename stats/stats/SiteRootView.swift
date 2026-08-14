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
    @State private var selectedYear: String = String(Calendar.current.component(.year, from: Date()))
    @State private var years: [String] = ["All years"]
    @State private var doublesEdit: DoublesGame?
    @State private var vollisEdit: VollisGame?
    @State private var addKind: GameSection = .doubles

    var body: some View {
        TabView(selection: $selectedTab) {
            SiteStatsView(section: $section, selectedYear: $selectedYear, years: years)
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(0)
            SiteGamesView(section: $section, selectedYear: $selectedYear, years: years, canEdit: auth.isLoggedIn, onEditDoubles: { doublesEdit = $0; addKind = .doubles; selectedTab = 2 }, onEditVollis: { vollisEdit = $0; addKind = .vollis; selectedTab = 2 })
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

    var body: some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $section) {
                ForEach(GameSection.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            Picker("Year", selection: $selectedYear) {
                ForEach(normalizedYears, id: \.self) { y in
                    Text(y == "All years" ? "All" : y).tag(displayTag(y))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal)
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

struct RankingTable: View {
    var title: String?
    var rows: [RankingRow]
    var showRating: Bool
    var showPlusMinus: Bool = false
    var year: String
    var section: GameSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline).padding(.horizontal)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                NavigationLink {
                    SitePlayerDetailView(name: row.name, year: year, section: section)
                } label: {
                    HStack {
                        Text("\(idx + 1)").frame(width: 28, alignment: .leading).foregroundStyle(.secondary)
                        Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
                        if showRating, let r = row.rating {
                            Text(String(format: "%.0f", r)).frame(width: 44, alignment: .trailing)
                        }
                        if showPlusMinus, let pm = row.plusMinus {
                            Text(pm > 0 ? "+\(pm)" : "\(pm)")
                                .foregroundStyle(pm >= 0 ? Color.green : Color.red)
                                .frame(width: 44, alignment: .trailing)
                        }
                        Text("\(row.wins)").frame(width: 32, alignment: .trailing).foregroundStyle(.green)
                        Text("\(row.losses)").frame(width: 32, alignment: .trailing).foregroundStyle(.red)
                        Text(row.winPctDisplay).frame(width: 48, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

struct SiteStatsView: View {
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
            ScrollView {
                SectionYearBar(section: $section, selectedYear: $selectedYear, years: years)
                TextField("Search players...", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
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
                            RankingTable(title: "Today's Stats", rows: filter(d.todayStats), showRating: false, showPlusMinus: true, year: d.displayYear, section: .doubles)
                        }
                        RankingTable(title: "Ranked", rows: filter(d.stats), showRating: true, year: d.displayYear, section: .doubles)
                        if !d.rareStats.isEmpty {
                            RankingTable(title: "Fewer than \(d.minimumGames) games", rows: filter(d.rareStats), showRating: true, year: d.displayYear, section: .doubles)
                        }
                    }
                case .vollis:
                    if let v = vollis {
                        RankingTable(title: nil, rows: filter(v.stats), showRating: false, year: v.displayYear, section: .vollis)
                    }
                case .other:
                    if let o = other {
                        ForEach(o.gameCards) { card in
                            RankingTable(title: card.gameName, rows: filter(card.stats), showRating: false, year: o.displayYear, section: .other)
                            if !card.rareStats.isEmpty {
                                RankingTable(title: "\(card.gameName ?? "") · rare", rows: filter(card.rareStats), showRating: false, year: o.displayYear, section: .other)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SiteCopyLinkButton(url: SitePublicLink.stats(section: section, year: selectedYear))
                }
            }
            .refreshable { await load() }
            .task(id: "\(section.rawValue)-\(selectedYear)") { await load() }
        }
    }

    private func filter(_ rows: [RankingRow]) -> [RankingRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return rows }
        return rows.filter { $0.name.lowercased().contains(q) }
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
                vollis = try await PythonAnywhereClient.shared.vollisStats(year: year)
            case .other:
                other = try await PythonAnywhereClient.shared.otherStats(year: year)
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct SiteGamesView: View {
    @Binding var section: GameSection
    @Binding var selectedYear: String
    var years: [String]
    var canEdit: Bool
    var onEditDoubles: (DoublesGame) -> Void
    var onEditVollis: (VollisGame) -> Void
    @State private var doubles: [DoublesGame] = []
    @State private var vollis: [VollisGame] = []
    @State private var other: [OtherGame] = []
    @State private var search = ""
    @State private var error: String?
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = SiteOfflineQueue.shared

    var body: some View {
        NavigationStack {
            VStack {
                SectionYearBar(section: $section, selectedYear: $selectedYear, years: years)
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                List {
                    switch section {
                    case .doubles:
                        ForEach(filteredDoubles) { g in
                            DoublesGameRow(game: g)
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
                        ForEach(filteredVollis) { g in
                            VStack(alignment: .leading) {
                                Text(g.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Text("\(g.winner ?? "")  \(g.winnerScore ?? 0)").foregroundStyle(.green)
                                    Spacer()
                                    Text("\(g.loserScore ?? 0)  \(g.loser ?? "")").foregroundStyle(.red)
                                }
                            }
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
                        ForEach(filteredOther) { g in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(g.gameName ?? "") · \(g.gameType ?? "")").font(.headline)
                                Text((g.gameDateOnly ?? g.gameDate) ?? "").font(.caption).foregroundStyle(.secondary)
                                Text(g.displayWinners.joined(separator: ", ")).foregroundStyle(.green)
                                Text(g.displayLosers.joined(separator: ", ")).foregroundStyle(.red)
                                if let c = g.comment, !c.isEmpty { Text(c).font(.caption).italic() }
                            }
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
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SiteCopyLinkButton(url: SitePublicLink.games(section: section, year: selectedYear))
                }
            }
            .refreshable { await load() }
            .task(id: "\(section.rawValue)-\(selectedYear)") { await load() }
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
        return other.filter { q.isEmpty || "\($0.gameName ?? "") \($0.displayWinners) \($0.displayLosers)".lowercased().contains(q) }
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

    private func deleteDoubles(_ g: DoublesGame) async {
        if !network.isConnected {
            queue.enqueue(method: "DELETE", path: "/api/doubles/games/\(g.id)", body: nil)
            doubles.removeAll { $0.id == g.id }
            return
        }
        do { try await PythonAnywhereClient.shared.deleteDoubles(id: g.id); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func deleteVollis(_ g: VollisGame) async {
        do { try await PythonAnywhereClient.shared.deleteVollis(id: g.id); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func deleteOther(_ g: OtherGame) async {
        do { try await PythonAnywhereClient.shared.deleteOther(id: g.id); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct DoublesGameRow: View {
    var game: DoublesGame
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.date, style: .date).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("\(game.winner1 ?? "") & \(game.winner2 ?? "")").foregroundStyle(.green)
                Spacer()
                Text("\(game.winnerScore ?? 0)")
            }
            HStack {
                Text("\(game.loser1 ?? "") & \(game.loser2 ?? "")").foregroundStyle(.red)
                Spacer()
                Text("\(game.loserScore ?? 0)")
            }
            if !game.comment.isEmpty { Text(game.comment).font(.caption).italic() }
            if let by = game.updatedBy, !by.isEmpty {
                Text("by \(by)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
