import SwiftUI

struct StatsView: View {
    @State private var games: [LegacyGame] = []
    @State private var isLoading = true
    @State private var selectedYear: Int = 2026
    
    @State private var playerStats: [PlayerStats] = []
    @State private var teamStats: [TeamStats] = []
    @State private var todayStats: DayStats?
    @State private var monthlyActivity: [MonthlyActivity] = []
    
    private let years = [2026, 2025, 2024, 2023, 2022, 2021, 2020, 2019, 2018, 2017, 2016]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.92, blue: 0.75),
                        Color(red: 0.85, green: 0.75, blue: 0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            yearPicker
                            
                            if let today = todayStats, !today.players.isEmpty {
                                todaySection(today)
                            }
                            
                            trueSkillSection
                            winPercentageSection
                            topTeamsSection
                            gamesPlayedSection
                            winningStreaksSection
                            losingStreaksSection
                            bestStreaksSection
                            worstStreaksSection
                            monthlySection
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("📊 Dashboard")
            .task {
                loadData()
            }
            .onChange(of: selectedYear) { _, _ in
                recalculateStats()
            }
        }
    }
    
    // MARK: - Year Picker
    
    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(years, id: \.self) { year in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedYear = year
                        }
                    } label: {
                        Text(String(year))
                            .font(.custom("AvenirNext-DemiBold", size: 14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedYear == year ?
                                          Color(red: 0.2, green: 0.4, blue: 0.6) :
                                            Color.white.opacity(0.7))
                            )
                            .foregroundStyle(selectedYear == year ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Today's Stats
    
    @ViewBuilder
    private func todaySection(_ stats: DayStats) -> some View {
        StatsSection(title: "Today's Stats", icon: "calendar") {
            VStack(spacing: 8) {
                ForEach(stats.players.prefix(10)) { player in
                    HStack {
                        Text(player.name)
                            .font(.custom("AvenirNext-DemiBold", size: 15))
                        
                        Spacer()
                        
                        Text(player.record)
                            .font(.custom("AvenirNext-Medium", size: 14))
                        
                        Text("(\(Int(player.winRate))%)")
                            .font(.custom("AvenirNext-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        Text(player.pointDiff >= 0 ? "+\(player.pointDiff)" : "\(player.pointDiff)")
                            .font(.custom("AvenirNext-Bold", size: 14))
                            .foregroundStyle(player.pointDiff >= 0 ? 
                                Color(red: 0.2, green: 0.5, blue: 0.3) : 
                                Color(red: 0.6, green: 0.35, blue: 0.3))
                            .frame(width: 45, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - TrueSkill Rankings
    // Minimum: 5 games (matches website)
    
    private var trueSkillSection: some View {
        let sortedPlayers = playerStats
            .filter { $0.games >= 5 }  // Minimum 5 games
            .sorted { $0.trueSkillExposed > $1.trueSkillExposed }
        
        return StatsSection(title: "TrueSkill Rankings", icon: "star.fill") {
            VStack(spacing: 6) {
                ForEach(Array(sortedPlayers.prefix(20).enumerated()), id: \.element.id) { index, player in
                    HStack {
                        Text("\(index + 1)")
                            .font(.custom("AvenirNext-Bold", size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        
                        Text(player.name)
                            .font(.custom("AvenirNext-DemiBold", size: 14))
                        
                        Spacer()
                        
                        Text(String(format: "%.1f", player.trueSkillExposed))
                            .font(.custom("AvenirNext-Bold", size: 15))
                            .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                            .frame(width: 44, alignment: .trailing)
                        
                        Text("\(player.record) (\(player.games) games)")
                            .font(.custom("AvenirNext-Regular", size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(index == 0 ? Color.yellow.opacity(0.2) : Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Win Percentage
    // Dynamic minimum based on total games in year (matches website behavior)
    
    private var winPercentageSection: some View {
        // Calculate total games from monthly activity for the selected year
        let totalGamesInYear = monthlyActivity
            .filter { $0.year == selectedYear }
            .reduce(0) { $0 + $1.gameCount }
        
        // Dynamic minimum: 5 games if <100 total games, otherwise 20 games
        let minGames = totalGamesInYear < 100 ? 5 : 20
        
        // Sort by win rate DESC, then by games played DESC as tiebreaker
        let sortedPlayers = playerStats
            .filter { $0.games >= minGames }
            .sorted { 
                if abs($0.winRate - $1.winRate) > 0.01 {
                    return $0.winRate > $1.winRate
                }
                return $0.games > $1.games
            }
        
        return StatsSection(title: "\(selectedYear) Win%", icon: "percent") {
            VStack(spacing: 6) {
                ForEach(Array(sortedPlayers.prefix(20).enumerated()), id: \.element.id) { index, player in
                    HStack {
                        Text(player.name)
                            .font(.custom("AvenirNext-DemiBold", size: 14))
                        
                        Spacer()
                        
                        // Win rate bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(winRateColor(player.winRate))
                                    .frame(width: geo.size.width * CGFloat(player.winRate / 100))
                            }
                        }
                        .frame(width: 60, height: 8)
                        
                        Text(String(format: "%.1f%%", player.winRate))
                            .font(.custom("AvenirNext-Bold", size: 14))
                            .foregroundStyle(winRateColor(player.winRate))
                            .frame(width: 55, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Top Teams
    // Dynamic minimum based on total games in year (matches website behavior)
    
    private var topTeamsSection: some View {
        // Calculate total games from monthly activity for the selected year
        let totalGamesInYear = monthlyActivity
            .filter { $0.year == selectedYear }
            .reduce(0) { $0 + $1.gameCount }
        
        // Dynamic minimum: 2 games if <100 total games, otherwise 10 games
        let minGames = totalGamesInYear < 100 ? 2 : 10
        
        // Sort by win rate DESC, then by wins DESC (tiebreaker), then alphabetically
        let sortedTeams = teamStats
            .filter { $0.games >= minGames }
            .sorted { 
                if abs($0.winRate - $1.winRate) > 0.01 {
                    return $0.winRate > $1.winRate
                }
                if $0.wins != $1.wins {
                    return $0.wins > $1.wins
                }
                return $0.displayName < $1.displayName
            }
        
        return StatsSection(title: "\(selectedYear) Top Teams", icon: "person.2.fill") {
            VStack(spacing: 6) {
                ForEach(Array(sortedTeams.prefix(20).enumerated()), id: \.element.id) { index, team in
                    HStack {
                        Text(team.displayName)
                            .font(.custom("AvenirNext-DemiBold", size: 13))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(team.wins)-\(team.losses)")
                            .font(.custom("AvenirNext-Regular", size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        
                        Text(String(format: "%.1f%%", team.winRate))
                            .font(.custom("AvenirNext-Bold", size: 14))
                            .foregroundStyle(winRateColor(team.winRate))
                            .frame(width: 55, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(team.winRate == 100 ? Color.green.opacity(0.1) : Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Games Played
    // No minimum - shows all players who played, sorted by most games
    
    private var gamesPlayedSection: some View {
        let sortedPlayers = playerStats
            .filter { $0.games >= 1 }  // Anyone who played at least 1 game
            .sorted { $0.games > $1.games }
        
        return StatsSection(title: "\(selectedYear) Games", icon: "volleyball.fill") {
            VStack(spacing: 6) {
                ForEach(Array(sortedPlayers.prefix(20).enumerated()), id: \.element.id) { index, player in
                    HStack {
                        Text(player.name)
                            .font(.custom("AvenirNext-DemiBold", size: 14))
                        
                        Spacer()
                        
                        Text("\(player.games) games")
                            .font(.custom("AvenirNext-Medium", size: 14))
                            .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Current Winning Streaks
    
    private var winningStreaksSection: some View {
        let streaking = playerStats.filter { $0.currentStreak > 0 }
            .sorted { $0.currentStreak > $1.currentStreak }
            .prefix(10)
        
        return StatsSection(title: "Current Win Streaks 🔥", icon: "flame.fill") {
            if streaking.isEmpty {
                Text("No active winning streaks")
                    .font(.custom("AvenirNext-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(streaking), id: \.id) { player in
                        HStack {
                            Text(player.name)
                                .font(.custom("AvenirNext-DemiBold", size: 14))
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text("\(player.currentStreak)")
                                    .font(.custom("AvenirNext-Bold", size: 16))
                                    .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.3))
                                Text("wins")
                                    .font(.custom("AvenirNext-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("(Best: \(player.bestWinStreak))")
                                .font(.custom("AvenirNext-Regular", size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
    
    // MARK: - Current Losing Streaks
    
    private var losingStreaksSection: some View {
        let streaking = playerStats.filter { $0.currentStreak < 0 }
            .sorted { $0.currentStreak < $1.currentStreak }
            .prefix(10)
        
        return StatsSection(title: "Current Lose Streaks 💀", icon: "xmark.circle.fill") {
            if streaking.isEmpty {
                Text("No active losing streaks")
                    .font(.custom("AvenirNext-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(streaking), id: \.id) { player in
                        HStack {
                            Text(player.name)
                                .font(.custom("AvenirNext-DemiBold", size: 14))
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text("\(abs(player.currentStreak))")
                                    .font(.custom("AvenirNext-Bold", size: 16))
                                    .foregroundStyle(Color(red: 0.6, green: 0.35, blue: 0.3))
                                Text("losses")
                                    .font(.custom("AvenirNext-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("(Worst: \(player.worstLoseStreak))")
                                .font(.custom("AvenirNext-Regular", size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 75, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
    
    // MARK: - Best Win Streaks (Historical)
    
    private var bestStreaksSection: some View {
        StatsSection(title: "Best Win Streaks (\(selectedYear))", icon: "trophy.fill") {
            VStack(spacing: 6) {
                ForEach(Array(playerStats.filter { $0.bestWinStreak > 0 }
                    .sorted { $0.bestWinStreak > $1.bestWinStreak }
                    .prefix(15)
                    .enumerated()), id: \.element.id) { index, player in
                    HStack {
                        Text(player.name)
                            .font(.custom("AvenirNext-DemiBold", size: 14))
                        
                        Spacer()
                        
                        Text("\(player.bestWinStreak) wins")
                            .font(.custom("AvenirNext-Bold", size: 14))
                            .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.3))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(index == 0 ? Color.yellow.opacity(0.2) : Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Worst Lose Streaks (Historical)
    
    private var worstStreaksSection: some View {
        StatsSection(title: "Worst Lose Streaks (\(selectedYear))", icon: "arrow.down.circle.fill") {
            VStack(spacing: 6) {
                ForEach(Array(playerStats.filter { $0.worstLoseStreak > 0 }
                    .sorted { $0.worstLoseStreak > $1.worstLoseStreak }
                    .prefix(15)
                    .enumerated()), id: \.element.id) { index, player in
                    HStack {
                        Text(player.name)
                            .font(.custom("AvenirNext-DemiBold", size: 14))
                        
                        Spacer()
                        
                        Text("\(player.worstLoseStreak) losses")
                            .font(.custom("AvenirNext-Bold", size: 14))
                            .foregroundStyle(Color(red: 0.6, green: 0.35, blue: 0.3))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Monthly Activity
    
    private var monthlySection: some View {
        let yearActivity = monthlyActivity.filter { $0.year == selectedYear }
        
        return StatsSection(title: "\(selectedYear) Monthly Activity", icon: "calendar.badge.clock") {
            if yearActivity.isEmpty {
                Text("No activity recorded")
                    .font(.custom("AvenirNext-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(spacing: 6) {
                    ForEach(yearActivity) { month in
                        HStack {
                            Text(month.monthName)
                                .font(.custom("AvenirNext-DemiBold", size: 14))
                            
                            Spacer()
                            
                            Text("\(month.gameCount) games")
                                .font(.custom("AvenirNext-Medium", size: 14))
                                .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func winRateColor(_ rate: Double) -> Color {
        if rate >= 70 { return Color(red: 0.2, green: 0.6, blue: 0.3) }
        if rate >= 50 { return Color(red: 0.2, green: 0.4, blue: 0.6) }
        if rate >= 30 { return Color(red: 0.7, green: 0.5, blue: 0.2) }
        return Color(red: 0.6, green: 0.35, blue: 0.3)
    }
    
    private func loadData() {
        Task {
            let loaded = DatabaseManager.shared.fetchAllGames()
            await MainActor.run {
                games = loaded
                recalculateStats()
                isLoading = false
            }
        }
    }
    
    private func recalculateStats() {
        // Pass all games for current streak calculation (streaks span all time)
        let result = StatsCalculator.calculateStats(
            from: games,
            year: selectedYear,
            allGamesForStreaks: games
        )
        playerStats = result.players
        teamStats = result.teams
        todayStats = result.todayStats
        monthlyActivity = result.monthlyActivity
    }
}

// MARK: - Stats Section Container

struct StatsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                    
                    Text(title)
                        .font(.custom("AvenirNext-Bold", size: 16))
                        .foregroundStyle(Color(red: 0.2, green: 0.3, blue: 0.4))
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.8))
            }
            
            if isExpanded {
                VStack(spacing: 0) {
                    content
                }
                .padding(12)
                .background(Color.white.opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}

#Preview {
    StatsView()
}
