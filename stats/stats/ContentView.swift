import SwiftUI

struct ContentView: View {
    @State private var games: [LegacyGame] = []
    @State private var showingAddGame = false
    @State private var gameToEdit: LegacyGame? = nil
    @State private var isLoading = true
    @State private var selectedYear: String = "All"
    
    private var yearsWithGames: [String] {
        guard !games.isEmpty else { return ["All"] }
        let calendar = Calendar.current
        let uniqueYears = Set(games.map { calendar.component(.year, from: $0.date) })
        return ["All"] + uniqueYears.sorted(by: >).map { String($0) }
    }
    
    var filteredGames: [LegacyGame] {
        if selectedYear == "All" {
            return games
        }
        let calendar = Calendar.current
        return games.filter { game in
            let year = calendar.component(.year, from: game.date)
            return String(year) == selectedYear
        }
    }
    
    private var playerStats: [PlayerRecord] {
        var wins: [String: Int] = [:]
        var losses: [String: Int] = [:]
        for game in filteredGames {
            for name in [game.winner1, game.winner2] where !name.trimmingCharacters(in: .whitespaces).isEmpty {
                wins[name, default: 0] += 1
            }
            for name in [game.loser1, game.loser2] where !name.trimmingCharacters(in: .whitespaces).isEmpty {
                losses[name, default: 0] += 1
            }
        }
        let allPlayers = Set(wins.keys).union(losses.keys)
        let gamesForSkill = filteredGames.filter { game in
            let w1 = game.winner1.trimmingCharacters(in: .whitespaces)
            let w2 = game.winner2.trimmingCharacters(in: .whitespaces)
            let l1 = game.loser1.trimmingCharacters(in: .whitespaces)
            let l2 = game.loser2.trimmingCharacters(in: .whitespaces)
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
                        mainList
                    }
                }
            }
            .navigationTitle("Beach Volleyball")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        gameToEdit = nil
                        showingAddGame = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    }
                }
            }
            .sheet(isPresented: $showingAddGame, onDismiss: { gameToEdit = nil }) {
                AddGameView(gameToEdit: gameToEdit) {
                    loadGames()
                }
            }
            .task {
                loadGames()
            }
            .onChange(of: yearsWithGames) { _, newYears in
                if !newYears.contains(selectedYear) {
                    selectedYear = "All"
                }
            }
            .navigationDestination(for: String.self) { playerName in
                PlayerDetailView(playerName: playerName, games: filteredGames)
            }
        }
    }
    
    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yearsWithGames, id: \.self) { year in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedYear = year
                        }
                    } label: {
                        Text(year)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(selectedYear == year ?
                                          Color(red: 1, green: 0.45, blue: 0.3) :
                                            Color.white.opacity(0.12))
                            )
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
            StatBox(value: "\(filteredGames.count)", label: "Games")
            
            let uniquePlayers = Set(
                filteredGames.flatMap { [$0.winner1, $0.winner2, $0.loser1, $0.loser2] }
            ).count
            StatBox(value: "\(uniquePlayers)", label: "Players")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.volleyball")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1, green: 0.45, blue: 0.3),
                            Color(red: 1, green: 0.35, blue: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("No Games Yet")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Tap + to record your first match")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            
            Button {
                gameToEdit = nil
                showingAddGame = true
            } label: {
                Label("Add Game", systemImage: "plus")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color(red: 1, green: 0.45, blue: 0.3))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }
    
    private var mainList: some View {
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
            
            Section {
                ForEach(filteredGames) { game in
                GameCard(game: game)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        gameToEdit = game
                        showingAddGame = true
                    }
                    .contextMenu {
                        Button {
                            gameToEdit = game
                            showingAddGame = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteGame(game)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteGame(game)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            gameToEdit = game
                            showingAddGame = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Color(red: 1, green: 0.45, blue: 0.3))
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
    }
    
    private func loadGames() {
        Task {
            let loaded = DatabaseManager.shared.fetchAllGames()
            await MainActor.run {
                games = loaded
                isLoading = false
            }
        }
    }
    
    private func deleteGame(_ game: LegacyGame) {
        if DatabaseManager.shared.deleteGame(id: game.id) {
            games.removeAll { $0.id == game.id }
        }
    }
}

struct StatBox: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

struct GameCard: View {
    let game: LegacyGame
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(game.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            
            HStack(spacing: 0) {
                VStack(alignment: .center, spacing: 2) {
                    Text(game.winner1.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : game.winner1)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(game.winner2.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : game.winner2)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    Text("\(game.winnerScore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 10)
                
                VStack(alignment: .center, spacing: 2) {
                    Text(game.loser1.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : game.loser1)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(game.loser2.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : game.loser2)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    Text("\(game.loserScore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .background(Color.white.opacity(0.04))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct PlayerRecord: Identifiable {
    let name: String
    let wins: Int
    let losses: Int
    let trueSkill: Double
    var id: String { name }
    var totalGames: Int { wins + losses }
    var winRate: Double { totalGames > 0 ? Double(wins) / Double(totalGames) * 100 : 0 }
}

struct PlayerStatRow: View {
    let stat: PlayerRecord
    
    var body: some View {
        HStack {
            Text(stat.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(String(format: "%.1f", stat.trueSkill))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                .frame(width: 36, alignment: .trailing)
            Text("\(stat.wins)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.6))
                .frame(width: 28, alignment: .trailing)
            Text("\(stat.losses)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                .frame(width: 28, alignment: .trailing)
            Text(String(format: "%.0f%%", stat.winRate))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                .frame(width: 40, alignment: .trailing)
            Text("\(stat.totalGames)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
