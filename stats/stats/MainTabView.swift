import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthManager.shared
    @State private var games: [LegacyGame] = []
    @State private var showingAddGame = false
    @State private var gameToEdit: LegacyGame? = nil
    @State private var isLoading = true
    @State private var selectedYear: String = "All"
    @State private var showingAuthSheet = false
    
    private var yearsWithGames: [String] {
        guard !games.isEmpty else { return ["All"] }
        let calendar = Calendar.current
        let uniqueYears = Set(games.map { calendar.component(.year, from: $0.date) })
        return ["All"] + uniqueYears.sorted(by: >).map { String($0) }
    }
    
    var filteredGames: [LegacyGame] {
        if selectedYear == "All" { return games }
        let calendar = Calendar.current
        return games.filter { String(calendar.component(.year, from: $0.date)) == selectedYear }
    }
    
    var body: some View {
        TabView {
            StatsPageView(
                games: filteredGames,
                isLoading: isLoading,
                selectedYear: $selectedYear,
                yearsWithGames: yearsWithGames,
                onRefresh: loadGames,
                onOpenAuth: { showingAuthSheet = true }
            )
            .tabItem {
                Label("Stats", systemImage: "chart.bar.fill")
            }
            
            GamesPageView(
                games: $games,
                filteredGames: filteredGames,
                isLoading: isLoading,
                selectedYear: $selectedYear,
                yearsWithGames: yearsWithGames,
                canEdit: auth.canEdit,
                onAdd: { gameToEdit = nil; showingAddGame = true },
                onEdit: { gameToEdit = $0; showingAddGame = true },
                onDelete: deleteGame,
                onGamesChanged: loadGames,
                onOpenAuth: { showingAuthSheet = true }
            )
            .tabItem {
                Label("Games", systemImage: "list.bullet")
            }
        }
        .tint(Color(red: 1, green: 0.45, blue: 0.3))
        .task {
            loadGames()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                loadGames()
            }
        }
        .onChange(of: yearsWithGames) { _, newYears in
            if !newYears.contains(selectedYear) { selectedYear = "All" }
        }
        .sheet(isPresented: $showingAddGame, onDismiss: { gameToEdit = nil }) {
            AddGameView(gameToEdit: gameToEdit) {
                loadGames()
            }
        }
        .sheet(isPresented: $showingAuthSheet) {
            AuthSheetView()
        }
    }
    
    private func loadGames() {
        DatabaseManager.shared.fetchAllGames { [self] loaded in
            games = loaded
            isLoading = false
        }
    }
    
    private func deleteGame(_ game: LegacyGame) {
        DatabaseManager.shared.deleteGame(id: game.id, recordName: game.recordName) { [self] success in
            if success {
                games.removeAll { $0.id == game.id }
            }
        }
    }
}

// MARK: - Stats Page (stats only)

struct StatsPageView: View {
    let games: [LegacyGame]
    let isLoading: Bool
    @Binding var selectedYear: String
    let yearsWithGames: [String]
    var onRefresh: (() -> Void)? = nil
    var onOpenAuth: () -> Void = {}
    
    private var playerStats: [PlayerRecord] {
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
        }.sorted { $0.trueSkill > $1.trueSkill }
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
                } else if games.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 0) {
                        yearPicker
                        statsSummary
                        statsList
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onOpenAuth()
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    }
                }
            }
            .navigationDestination(for: String.self) { playerName in
                PlayerDetailView(playerName: playerName, games: games)
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
    
    private var statsSummary: some View {
        HStack(spacing: 20) {
            StatBox(value: "\(games.count)", label: "Games")
            let uniquePlayers = Set(games.flatMap { [$0.winner1, $0.winner2, $0.loser1, $0.loser2] }).count
            StatBox(value: "\(uniquePlayers)", label: "Players")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar")
                .font(.system(size: 64))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3).opacity(0.8))
            Text("No Data Yet")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Add games on the Games tab to see stats")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
    
    private var statsList: some View {
        List {
            Section {
                HStack {
                    Text("Player")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("Skill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, alignment: .trailing)
                    Text("W")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, alignment: .trailing)
                    Text("L")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, alignment: .trailing)
                    Text("Win%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 40, alignment: .trailing)
                    Text("Total")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                
                ForEach(playerStats) { stat in
                    NavigationLink(value: stat.name) {
                        PlayerStatRow(stat: stat)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.white.opacity(0.04))
                }
            } header: {
                Text("Player Stats")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            onRefresh?()
        }
    }
}

// MARK: - Games Page (games only)

struct GamesPageView: View {
    @Binding var games: [LegacyGame]
    let filteredGames: [LegacyGame]
    let isLoading: Bool
    @Binding var selectedYear: String
    let yearsWithGames: [String]
    let canEdit: Bool
    let onAdd: () -> Void
    let onEdit: (LegacyGame) -> Void
    let onDelete: (LegacyGame) -> Void
    let onGamesChanged: () -> Void
    var onOpenAuth: () -> Void = {}
    
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
                } else if filteredGames.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 0) {
                        yearPicker
                        gamesList
                    }
                }
            }
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        if canEdit {
                            Button {
                                onAdd()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                            }
                        }
                        Button {
                            onOpenAuth()
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.title3)
                                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                        }
                    }
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
            Section {
                ForEach(filteredGames) { game in
                    GameCard(game: game)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if canEdit { onEdit(game) }
                        }
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
            } header: {
                Text("Games")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            onGamesChanged()
        }
    }
}

// MARK: - Auth Sheet (share code / join)

struct AuthSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared
    @State private var joinCode = ""
    @State private var showCopied = false
    @State private var isCreating = false
    @State private var isJoining = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    if auth.isOwner {
                        ownerView
                    } else if auth.enteredCode != nil {
                        joinedView
                    } else {
                        noAccessView
                    }
                    Spacer()
                }
                .padding(.top, 32)
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
        }
    }
    
    private var navTitle: String {
        if auth.isOwner { return "Share Access" }
        if auth.enteredCode != nil { return "Access" }
        return "Add or Edit Games"
    }
    
    private var ownerView: some View {
        VStack(spacing: 12) {
            Text("Share this code so others can add games to your database")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Text(auth.shareCode.isEmpty ? "------" : auth.shareCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                .tracking(4)
            Button {
                auth.ensureOwnerCode()
                UIPasteboard.general.string = auth.shareCode
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                Label(showCopied ? "Copied!" : "Copy Code", systemImage: "doc.on.doc")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color(red: 1, green: 0.45, blue: 0.3)))
            }
            .buttonStyle(.plain)
            .disabled(showCopied || auth.shareCode.isEmpty)
        }
        .padding()
    }
    
    private var joinedView: some View {
        VStack(spacing: 16) {
            Text("You can add and edit games.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Button(role: .destructive) {
                CloudKitManager.shared.clearSharedDatabase()
                auth.leave()
                dismiss()
            } label: {
                Text("Leave (view only)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }
            .padding(.top, 8)
        }
        .padding()
    }
    
    private var noAccessView: some View {
        VStack(spacing: 20) {
            if let msg = errorMessage {
                Text(msg)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                    .multilineTextAlignment(.center)
            }
            Text("Only people with access can add or edit games. Create a database to get a share code, or join with a code from the owner.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Button {
                errorMessage = nil
                isCreating = true
                CloudKitManager.shared.createSharedDatabase { result in
                    DispatchQueue.main.async {
                        isCreating = false
                        switch result {
                        case .success(let code):
                            auth.isOwner = true
                            auth.shareCode = code
                            dismiss()
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                }
            } label: {
                Group {
                    if isCreating {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Label("Create database (get share code)", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color(red: 1, green: 0.45, blue: 0.3)))
            }
            .buttonStyle(.plain)
            .disabled(isCreating)
            
            Text("or")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            
            TextField("Enter 6-character code", text: $joinCode)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            
            Button {
                errorMessage = nil
                isJoining = true
                CloudKitManager.shared.acceptShare(code: joinCode) { result in
                    DispatchQueue.main.async {
                        isJoining = false
                        switch result {
                        case .success:
                            auth.join(with: joinCode)
                            dismiss()
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                }
            } label: {
                Group {
                    if isJoining {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Join with code")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color(red: 0.3, green: 0.7, blue: 0.5)))
            }
            .buttonStyle(.plain)
            .disabled(isJoining || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
        }
        .padding()
    }
}

#Preview {
    MainTabView()
}
