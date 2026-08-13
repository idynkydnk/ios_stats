import SwiftUI

/// Max games fetched for the Games (and Stats) tab to reduce Firestore reads. User still sees most recent games.
private let gamesTabPageSize = 25

private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var dbOwner = DatabaseOwnerManager.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var localCache = LocalDatabaseCache.shared
    @State private var statsSource: StatsSource = .myDatabase
    @State private var otherDatabaseGames: [LegacyGame] = []
    @State private var selectedTab = 0
    @State private var gameToEdit: LegacyGame? = nil
    @State private var isLoading = false
    @State private var selectedYear: String = String(Calendar.current.component(.year, from: Date()))
    @State private var isLoadingMore = false
    @State private var gamesDisplayLimit = 25
    @State private var fetchedStats: [PlayerRecord]? = nil
    @State private var statsYears: [String] = ["All"]
    @State private var isLoadingStats = false

    private var currentDbId: String? {
        statsSource.cloudDbId(owner: dbOwner)
    }

    private var games: [LegacyGame] {
        switch statsSource {
        case .myDatabase: return localCache.games
        case .other(_, _): return otherDatabaseGames
        }
    }

    private var yearsWithGames: [String] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        var uniqueYears = games.isEmpty ? Set<Int>() : Set(games.map { calendar.component(.year, from: $0.date) })
        uniqueYears.insert(currentYear)
        return ["All"] + uniqueYears.sorted(by: >).map { String($0) }
    }

    var filteredGames: [LegacyGame] {
        if selectedYear == "All" { return games }
        let calendar = Calendar.current
        return games.filter { String(calendar.component(.year, from: $0.date)) == selectedYear }
    }

    /// Main tabs show local stats only; use Browse to view your or others' cloud databases.
    private var canShowMyDatabase: Bool { false }
    private var canEditCurrent: Bool {
        switch statsSource {
        case .myDatabase: return dbOwner.myDbId.map { dbOwner.canEdit(dbId: $0) } ?? false
        case .other(let dbId, _): return dbOwner.canEdit(dbId: dbId)
        }
    }

    private var statsTabContent: some View {
        StatsPageView(
            games: filteredGames,
            statsOverride: fetchedStats,
            isLoading: isLoading,
            isLoadingStats: isLoadingStats,
            selectedYear: $selectedYear,
            yearsWithGames: fetchedStats != nil ? statsYears : yearsWithGames,
            statsSource: $statsSource,
            sourceDisplayName: statsSource.headerDisplayName(owner: dbOwner),
            cloudDbId: currentDbId,
            canShowMyDatabase: canShowMyDatabase,
            canEdit: canEditCurrent,
            onRefresh: { loadGames(); loadStats() },
            onAdd: { gameToEdit = nil; selectedTab = 2 },
            onOpenDatabases: { selectedTab = 3 }
        )
        .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
        .tag(0)
    }

    private var gamesTabContent: some View {
        GamesPageView(
            games: .constant(games),
            filteredGames: filteredGames,
            displayedGamesLimit: 0,
            isLoading: isLoading,
            selectedYear: $selectedYear,
            yearsWithGames: yearsWithGames,
            statsSource: $statsSource,
            sourceDisplayName: statsSource.headerDisplayName(owner: dbOwner),
            canShowMyDatabase: canShowMyDatabase,
            canEdit: canEditCurrent,
            canLoadMore: currentDbId.map { cloud.hasMoreGames(dbId: $0) } ?? false,
            isLoadingMore: isLoadingMore,
            onLoadMore: loadMoreGames,
            onAdd: { gameToEdit = nil; selectedTab = 2 },
            onEdit: { gameToEdit = $0; selectedTab = 2 },
            onDelete: deleteGame,
            onGamesChanged: loadGames,
            onOpenDatabases: { selectedTab = 3 }
        )
        .tabItem { Label("Games", systemImage: "list.bullet") }
        .tag(1)
    }

    private var addGameTabContent: some View {
        NavigationStack {
            AddGameView(
                gameToEdit: gameToEdit,
                statsSource: statsSource,
                cloudDbId: statsSource.cloudDbId(owner: dbOwner),
                editorDbId: dbOwner.myDbId,
                isOnline: network.isConnected,
                onSave: { loadGames() },
                onSaveToLocal: { game in
                    guard let dbId = dbOwner.myDbId else { return }
                    localCache.append(game, dbId: dbId)
                },
                onDismiss: { selectedTab = 1; gameToEdit = nil }
            )
        }
        .tabItem { Label("Add Game", systemImage: "plus.circle.fill") }
        .tag(2)
    }

    private var browseTabContent: some View {
        BrowseDatabasesView(onSelectDatabase: { dbId, displayName in
            statsSource = .other(dbId: dbId, displayName: displayName)
            loadGames()
            selectedTab = 1
        })
        .tabItem { Label("Databases", systemImage: "tray.full") }
        .tag(3)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            statsTabContent
            gamesTabContent
            addGameTabContent
            browseTabContent
        }
        .tint(Color(red: 1, green: 0.45, blue: 0.3))
        .task {
            localCache.loadForDatabase(dbId: dbOwner.myDbId)
            cloud.fetchDefaultDatabase { [self] result in
                if case .success(let pair) = result, let (id, name) = pair {
                    statsSource = .other(dbId: id, displayName: name)
                }
                loadGames()
                loadStats()
                if let dbId = statsSource.cloudDbId(owner: dbOwner) {
                    cloud.prefetchPlayers(dbId: dbId, editorDbId: dbOwner.myDbId)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                loadGames()
            }
        }
        .onChange(of: statsSource) { _, _ in
            loadGames()
            loadStats()
        }
        .onChange(of: yearsWithGames) { _, newYears in
            if !newYears.contains(selectedYear) { selectedYear = newYears.first { $0 != "All" } ?? "All" }
        }
        .onChange(of: selectedYear) { _, _ in
            loadStats()
        }
        .onChange(of: dbOwner.myDbId) { _, dbId in
            localCache.loadForDatabase(dbId: dbId)
        }
        .onChange(of: network.isConnected) { _, isConnected in
            if isConnected, let dbId = dbOwner.myDbId {
                syncPendingAndRefresh(dbId: dbId)
            }
        }
    }

    private func loadGames() {
        gamesDisplayLimit = 25
        switch statsSource {
        case .myDatabase:
            guard let dbId = dbOwner.myDbId else {
                localCache.loadForDatabase(dbId: nil)
                isLoading = false
                return
            }
            if network.isConnected {
                if localCache.games.isEmpty { isLoading = true }
                cloud.fetchGames(dbId: dbId, limit: gamesTabPageSize) { [self] result in
                    switch result {
                    case .success(let loaded):
                        localCache.replaceWith(loaded, dbId: dbId)
                    case .failure:
                        localCache.loadForDatabase(dbId: dbId)
                    }
                    isLoading = false
                }
            } else {
                localCache.loadForDatabase(dbId: dbId)
                isLoading = false
            }
        case .other(let dbId, _):
            if otherDatabaseGames.isEmpty { isLoading = true }
            cloud.fetchGames(dbId: dbId, limit: gamesTabPageSize) { [self] result in
                switch result {
                case .success(let loaded):
                    otherDatabaseGames = loaded
                case .failure:
                    break
                }
                isLoading = false
            }
        }
    }

    private func loadStats() {
        guard let dbId = currentDbId else {
            fetchedStats = nil
            return
        }
        isLoadingStats = true
        cloud.fetchPlayerStats(dbId: dbId, year: selectedYear) { [self] result in
            isLoadingStats = false
            switch result {
            case .success(let (list, years)):
                fetchedStats = list.map { PlayerRecord(name: $0.name, wins: $0.wins, losses: $0.losses, trueSkill: $0.trueSkill) }
                statsYears = years
            case .failure:
                fetchedStats = nil
            }
        }
    }

    private func loadMoreGames() {
        guard let dbId = currentDbId else { return }
        isLoadingMore = true
        cloud.loadMoreGames(dbId: dbId, limit: gamesTabPageSize) { [self] result in
            isLoadingMore = false
            switch result {
            case .success(let nextPage):
                guard !nextPage.isEmpty else { return }
                switch statsSource {
                case .myDatabase:
                    localCache.appendPage(nextPage, dbId: dbId)
                case .other:
                    otherDatabaseGames = (otherDatabaseGames + nextPage).sorted { $0.date > $1.date }
                }
            case .failure:
                break
            }
        }
    }

    private func deleteGame(_ game: LegacyGame) {
        guard let recordName = game.recordName else { return }
        switch statsSource {
        case .myDatabase:
            guard let dbId = dbOwner.myDbId else { return }
            localCache.remove(recordName: recordName, dbId: dbId)
            if network.isConnected && !recordName.hasPrefix("offline-") {
                cloud.deleteGame(dbId: dbId, documentId: recordName, editorDbId: dbOwner.myDbId) { _ in }
            }
        case .other(let dbId, _):
            cloud.deleteGame(dbId: dbId, documentId: recordName, editorDbId: dbOwner.myDbId) { [self] result in
                switch result {
                case .success:
                    otherDatabaseGames.removeAll { $0.recordName == recordName }
                case .failure:
                    break
                }
            }
        }
    }

    /// When back online: upload offline-added games to Firestore, then fetch and replace local cache.
    private func syncPendingAndRefresh(dbId: String) {
        let pending = localCache.pendingOfflineGames()
        guard !pending.isEmpty else {
            loadGames()
            return
        }
        var remaining = pending
        func uploadNext() {
            guard let game = remaining.first else {
                loadGames()
                return
            }
            remaining.removeFirst()
            cloud.insertGame(dbId: dbId, date: game.date, winner1: game.winner1, winner2: game.winner2, winnerScore: game.winnerScore, loser1: game.loser1, loser2: game.loser2, loserScore: game.loserScore, comment: game.comment, editorDbId: dbOwner.myDbId) { [self] result in
                switch result {
                case .success:
                    localCache.remove(recordName: game.recordName ?? "", dbId: dbId)
                case .failure:
                    break
                }
                uploadNext()
            }
        }
        uploadNext()
    }
}

// MARK: - Stats sort column (for Stats page)

private enum StatsSortColumn {
    case player, rating, wins, losses, winPct, games
}

// MARK: - Stats Page (stats only)

struct StatsPageView: View {
    let games: [LegacyGame]
    var statsOverride: [PlayerRecord]? = nil
    let isLoading: Bool
    var isLoadingStats: Bool = false
    @Binding var selectedYear: String
    let yearsWithGames: [String]
    @Binding var statsSource: StatsSource
    var sourceDisplayName: String = "My database"
    var cloudDbId: String? = nil
    let canShowMyDatabase: Bool
    let canEdit: Bool
    var onRefresh: (() -> Void)? = nil
    var onAdd: () -> Void = {}
    var onOpenDatabases: () -> Void = {}
    @State private var playerNavigationPath = NavigationPath()
    @State private var statsSortColumn: StatsSortColumn = .rating
    @State private var statsSortAscending: Bool = false
    @State private var searchText = ""

    private var searchFilteredPlayerStats: [PlayerRecord] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return sortedPlayerStats }
        return sortedPlayerStats.filter { $0.name.lowercased().contains(term) }
    }

    private var playerStats: [PlayerRecord] {
        if let override = statsOverride, !override.isEmpty {
            return override
        }
        var wins: [String: Int] = [:]
        var losses: [String: Int] = [:]
        for game in games {
            for name in [game.winner1, game.winner2] where !name.trimmingCharacters(in: .whitespaces).isEmpty {
                wins[name, default: 0] += 1
            }
            for name in [game.loser1, game.loser2] where !name.trimmingCharacters(in: .whitespaces).isEmpty {
                losses[name, default: 0] += 1
            }
        }
        let allPlayers = Set(wins.keys).union(losses.keys)
        let gamesForSkill = games.filter { g in
            let w1 = g.winner1.trimmingCharacters(in: .whitespaces)
            let w2 = g.winner2.trimmingCharacters(in: .whitespaces)
            let l1 = g.loser1.trimmingCharacters(in: .whitespaces)
            let l2 = g.loser2.trimmingCharacters(in: .whitespaces)
            return !w1.isEmpty && !w2.isEmpty && !l1.isEmpty && !l2.isEmpty
        }
        let trueSkillRatings = TrueSkillRatingSystem.calculateRatings(from: gamesForSkill)
        return allPlayers.map { name in
            let w = wins[name] ?? 0
            let l = losses[name] ?? 0
            let skill = trueSkillRatings[name]?.exposed ?? 0
            return PlayerRecord(name: name, wins: w, losses: l, trueSkill: skill)
        }
    }

    private var sortedPlayerStats: [PlayerRecord] {
        let sorted: [PlayerRecord]
        switch statsSortColumn {
        case .player:
            sorted = playerStats.sorted { statsSortAscending ? $0.name < $1.name : $0.name > $1.name }
        case .rating:
            sorted = playerStats.sorted { statsSortAscending ? $0.trueSkill < $1.trueSkill : $0.trueSkill > $1.trueSkill }
        case .wins:
            sorted = playerStats.sorted { statsSortAscending ? $0.wins < $1.wins : $0.wins > $1.wins }
        case .losses:
            sorted = playerStats.sorted { statsSortAscending ? $0.losses < $1.losses : $0.losses > $1.losses }
        case .winPct:
            sorted = playerStats.sorted { statsSortAscending ? $0.winRate < $1.winRate : $0.winRate > $1.winRate }
        case .games:
            sorted = playerStats.sorted { statsSortAscending ? $0.totalGames < $1.totalGames : $0.totalGames > $1.totalGames }
        }
        return sorted
    }
    
    var body: some View {
        NavigationStack(path: $playerNavigationPath) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.1, blue: 0.16),
                        Color(red: 0.1, green: 0.14, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if isLoading || isLoadingStats {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color(red: 1, green: 0.45, blue: 0.3))
                } else {
                    VStack(spacing: 0) {
                        statsSourcePicker
                        if games.isEmpty && (statsOverride == nil || statsOverride?.isEmpty == true) {
                            emptyStateView
                        } else {
                            yearPicker
                            statsSummary
                            statsSearchBar
                            statsList
                        }
                    }
                }
            }
            .navigationTitle("Stats (\(sourceDisplayName))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
            .navigationDestination(for: String.self) { playerName in
                PlayerDetailView(playerName: playerName, games: games, cloudDbId: cloudDbId)
            }
        }
    }
    
    private var statsSourcePicker: some View {
        Group {
            if canShowMyDatabase {
                Picker("Stats", selection: $statsSource) {
                    Text(StatsSource.myDatabase.displayName).tag(StatsSource.myDatabase)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private var statsSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search players", text: $searchText)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .submitLabel(.done)
                .onSubmit { dismissKeyboard() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yearsWithGames, id: \.self) { year in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedYear = year }
                    } label: {
                        Text(year)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(selectedYear == year ? Color(red: 1, green: 0.45, blue: 0.3) : Color.white.opacity(0.12)))
                            .foregroundStyle(selectedYear == year ? .black : .white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var statsSummary: some View {
        HStack(spacing: 20) {
            let (gameCount, playerCount) = statsSummaryCounts
            StatBox(value: "\(gameCount)", label: "Games")
            StatBox(value: "\(playerCount)", label: "Players")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var statsSummaryCounts: (gameCount: Int, playerCount: Int) {
        if let stats = statsOverride, !stats.isEmpty {
            let totalGames = stats.reduce(0) { $0 + $1.wins } / 2
            return (totalGames, stats.count)
        }
        let uniquePlayers = Set(games.flatMap { [$0.winner1, $0.winner2, $0.loser1, $0.loser2] }).count
        return (games.count, uniquePlayers)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar")
                .font(.system(size: 64))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3).opacity(0.8))
            Text("No Data Yet")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(canEdit ? "Add games to see stats" : "No games yet")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            if canEdit {
                Button {
                    onAdd()
                } label: {
                    Label("Add Game", systemImage: "plus")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color(red: 1, green: 0.45, blue: 0.3)))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }
    
    private func sortHeader(_ column: StatsSortColumn, title: String, width: CGFloat? = nil) -> some View {
        let isActive = statsSortColumn == column
        return Button {
            if statsSortColumn == column {
                statsSortAscending.toggle()
            } else {
                statsSortColumn = column
                switch column {
                case .player: statsSortAscending = true   // A–Z
                case .rating, .wins, .winPct, .games: statsSortAscending = false  // high first
                case .losses: statsSortAscending = true  // fewest losses first
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? Color(red: 1, green: 0.45, blue: 0.3) : .white.opacity(0.5))
                if isActive {
                    Image(systemName: statsSortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: width == nil ? .leading : .center)
            .frame(width: width)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private var statsList: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    sortHeader(.player, title: "Player")
                    sortHeader(.rating, title: "Rating", width: 36)
                    sortHeader(.wins, title: "Wins", width: 40)
                    sortHeader(.losses, title: "Losses", width: 52)
                    sortHeader(.winPct, title: "Win%", width: 40)
                    sortHeader(.games, title: "Games", width: 44)
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchFilteredPlayerStats.isEmpty {
                    Text("No players match \"\(searchText)\"")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(searchFilteredPlayerStats) { stat in
                    Button {
                        playerNavigationPath.append(stat.name)
                    } label: {
                        PlayerStatRow(stat: stat)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.white.opacity(0.04))
                }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            onRefresh?()
        }
    }
}

// MARK: - Player stats types (used by StatsPageView)

struct PlayerRecord: Identifiable {
    let name: String
    let wins: Int
    let losses: Int
    let trueSkill: Double
    var id: String { name }
    var totalGames: Int { wins + losses }
    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames) * 100
    }
}

private struct PlayerStatRow: View {
    let stat: PlayerRecord
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(stat.name)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(Int(round(stat.trueSkill))))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.65, blue: 0.4))
                .frame(width: 36, alignment: .center)
            Text("\(stat.wins)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, alignment: .center)
            Text("\(stat.losses)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 52, alignment: .center)
            Text(String(format: "%.0f%%", stat.winRate))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, alignment: .center)
            Text("\(stat.totalGames)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44, alignment: .center)
        }
        .padding(.vertical, 4)
    }
}

private struct StatBox: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GameCard: View {
    let game: LegacyGame
    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: game.date)
    }
    private var winner1Text: String {
        let s = game.winner1.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "—" : s
    }
    private var winner2Text: String {
        let s = game.winner2.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "—" : s
    }
    private var loser1Text: String {
        let s = game.loser1.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "—" : s
    }
    private var loser2Text: String {
        let s = game.loser2.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "—" : s
    }
    private let winnerColor = Color(red: 0.3, green: 0.85, blue: 0.6)
    private let loserColor = Color(red: 1, green: 0.4, blue: 0.35)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Date/time header centered
            Text(dateString)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
            
            // Two side-by-side team cards: names on top, score underneath each
            HStack(spacing: 10) {
                // Winners card (green)
                VStack(spacing: 6) {
                    Text(winner1Text)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(winner2Text)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("\(game.winnerScore)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(winnerColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background(winnerColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(winnerColor.opacity(0.5), lineWidth: 1)
                )
                
                // Losers card (red)
                VStack(spacing: 6) {
                    Text(loser1Text)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(loser2Text)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("\(game.loserScore)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(loserColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background(loserColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(loserColor.opacity(0.5), lineWidth: 1)
                )
            }
            
            if !game.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(game.comment)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Games Page (games only)

struct GamesPageView: View {
    @Binding var games: [LegacyGame]
    let filteredGames: [LegacyGame]
    /// When set, Games list shows only this many (client-side pagination). Omit or 0 = show all.
    var displayedGamesLimit: Int = 0
    let isLoading: Bool
    @Binding var selectedYear: String
    let yearsWithGames: [String]
    @Binding var statsSource: StatsSource
    var sourceDisplayName: String = "My database"
    let canShowMyDatabase: Bool
    let canEdit: Bool
    var canLoadMore: Bool = false
    var isLoadingMore: Bool = false
    var onLoadMore: () -> Void = {}
    let onAdd: () -> Void
    let onEdit: (LegacyGame) -> Void
    let onDelete: (LegacyGame) -> Void
    let onGamesChanged: () -> Void
    var onOpenDatabases: () -> Void = {}

    @State private var searchText = ""
    @State private var displayedSearchCount = 25

    private var searchFilteredGames: [LegacyGame] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return filteredGames }
        return filteredGames.filter { game in
            [game.winner1, game.winner2, game.loser1, game.loser2, game.comment]
                .contains { $0.lowercased().contains(term) }
        }
    }

    private var gamesToShow: [LegacyGame] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(searchFilteredGames.prefix(displayedSearchCount))
        }
        if displayedGamesLimit > 0 {
            return Array(filteredGames.prefix(displayedGamesLimit))
        }
        return filteredGames
    }

    private var canShowSearchLoadMore: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        displayedSearchCount < searchFilteredGames.count
    }

    private var statsSourcePicker: some View {
        Group {
            if canShowMyDatabase {
                Picker("Games", selection: $statsSource) {
                    Text(StatsSource.myDatabase.displayName).tag(StatsSource.myDatabase)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private var gamesSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search players or comment", text: $searchText)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .submitLabel(.done)
                .onSubmit { dismissKeyboard() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.1, blue: 0.16),
                        Color(red: 0.1, green: 0.14, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color(red: 1, green: 0.45, blue: 0.3))
                } else {
                    VStack(spacing: 0) {
                        statsSourcePicker
                        if filteredGames.isEmpty {
                            emptyStateView
                        } else {
                            yearPicker
                            gamesSearchBar
                            gamesList
                            if displayedGamesLimit > 0, filteredGames.count > displayedGamesLimit, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Showing \(gamesToShow.count) of \(filteredGames.count) games")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
            }
            .onChange(of: searchText) { _, _ in
                displayedSearchCount = 25
            }
            .navigationTitle("Games (\(sourceDisplayName))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
        }
    }
    
    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yearsWithGames, id: \.self) { year in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedYear = year }
                    } label: {
                        Text(year)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(selectedYear == year ? Color(red: 1, green: 0.45, blue: 0.3) : Color.white.opacity(0.12)))
                            .foregroundStyle(selectedYear == year ? .black : .white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "list.bullet")
                .font(.system(size: 64))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3).opacity(0.8))
            Text("No Games Yet")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(canEdit ? "Tap + to add your first game" : "Only people with access can add games")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            if canEdit {
                Button {
                    onAdd()
                } label: {
                    Label("Add Game", systemImage: "plus")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color(red: 1, green: 0.45, blue: 0.3)))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }
    
    private var gamesList: some View {
        List {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchFilteredGames.isEmpty {
                Section {
                    Text("No matches for \"\(searchText)\"")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(gamesToShow) { game in
                    GameCard(game: game)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            if canEdit {
                                Button {
                                    onEdit(game)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    onDelete(game)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if canEdit {
                                Button(role: .destructive) {
                                    onDelete(game)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if canEdit {
                                Button {
                                    onEdit(game)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color(red: 1, green: 0.45, blue: 0.3))
                            }
                        }
                }
            }
            }
            if canShowSearchLoadMore {
                Section {
                    Button {
                        displayedSearchCount += gamesTabPageSize
                    } label: {
                        HStack {
                            Spacer()
                            Text("Load more (\(displayedSearchCount) of \(searchFilteredGames.count) shown)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if canLoadMore {
                Section {
                    Button {
                        onLoadMore()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView().scaleEffect(0.9).tint(Color(red: 1, green: 0.45, blue: 0.3))
                                Text("Loading…")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Load more")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .disabled(isLoadingMore)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            onGamesChanged()
        }
    }
}

#Preview {
    MainTabView()
}
