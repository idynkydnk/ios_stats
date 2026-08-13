import Foundation

// MARK: - Stat Models

struct PlayerStats: Identifiable {
    var id: String { name }
    let name: String
    var wins: Int = 0
    var losses: Int = 0
    var pointDiff: Int = 0
    var currentStreak: Int = 0  // positive = wins, negative = losses (calculated from most recent games)
    var bestWinStreak: Int = 0  // best winning streak for the selected period
    var worstLoseStreak: Int = 0  // worst losing streak for the selected period
    
    // TrueSkill values
    var trueSkillMu: Double = 25.0
    var trueSkillSigma: Double = 25.0 / 3.0
    var trueSkillExposed: Double = 0.0  // mu - 3*sigma (conservative estimate)
    
    var games: Int { wins + losses }
    var winRate: Double { games > 0 ? Double(wins) / Double(games) * 100 : 0 }
    var record: String { "\(wins)-\(losses)" }
}

struct TeamStats: Identifiable, Hashable {
    var id: String { "\(player1)|\(player2)" }
    let player1: String
    let player2: String
    var wins: Int = 0
    var losses: Int = 0
    
    var games: Int { wins + losses }
    var winRate: Double { games > 0 ? Double(wins) / Double(games) * 100 : 0 }
    
    var displayName: String {
        "\(player1) & \(player2)"
    }
    
    // Create normalized team key (alphabetically sorted)
    static func makeKey(p1: String, p2: String) -> String {
        if p1 < p2 {
            return "\(p1)|\(p2)"
        } else {
            return "\(p2)|\(p1)"
        }
    }
    
    init(player1: String, player2: String) {
        // Always store in alphabetical order for consistency
        if player1 < player2 {
            self.player1 = player1
            self.player2 = player2
        } else {
            self.player1 = player2
            self.player2 = player1
        }
    }
}

struct DayStats {
    let date: Date
    var players: [PlayerStats]
}

struct MonthlyActivity: Identifiable {
    var id: String { "\(year)-\(month)" }
    let year: Int
    let month: Int
    var gameCount: Int
    
    var monthName: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM"
        var components = DateComponents()
        components.month = month
        components.year = year
        if let date = Calendar.current.date(from: components) {
            return df.string(from: date)
        }
        return ""
    }
}

// MARK: - Stats Calculator

final class StatsCalculator {
    
    /// Calculate all stats from games
    /// - Parameters:
    ///   - games: All games from database
    ///   - year: Optional year to filter stats (nil = all years)
    ///   - allGamesForStreaks: All games (used for calculating current streaks which span all time)
    static func calculateStats(
        from games: [LegacyGame],
        year: Int? = nil,
        allGamesForStreaks: [LegacyGame]? = nil
    ) -> (
        players: [PlayerStats],
        teams: [TeamStats],
        todayStats: DayStats?,
        monthlyActivity: [MonthlyActivity]
    ) {
        let calendar = Calendar.current
        
        // Filter by year if specified
        let filteredGames: [LegacyGame]
        if let year = year {
            filteredGames = games.filter { calendar.component(.year, from: $0.date) == year }
        } else {
            filteredGames = games
        }
        
        // Sort games by date (oldest first for processing)
        let sortedGames = filteredGames.sorted { $0.date < $1.date }
        
        var playerStatsMap: [String: PlayerStats] = [:]
        var teamStatsMap: [String: TeamStats] = [:]
        var monthlyMap: [String: MonthlyActivity] = [:]
        
        // Track best/worst streaks during the period
        var runningStreaks: [String: Int] = [:]  // current running streak while processing
        var bestWinStreaks: [String: Int] = [:]
        var worstLoseStreaks: [String: Int] = [:]
        
        // Process each game
        for game in sortedGames {
            let winners = [game.winner1, game.winner2]
            let losers = [game.loser1, game.loser2]
            let allPlayers = winners + losers
            
            // Initialize player stats if needed
            for player in allPlayers {
                if playerStatsMap[player] == nil {
                    playerStatsMap[player] = PlayerStats(name: player)
                }
            }
            
            // Update wins/losses and point differential
            for winner in winners {
                playerStatsMap[winner]?.wins += 1
                playerStatsMap[winner]?.pointDiff += (game.winnerScore - game.loserScore)
                
                // Update running streak for best streak calculation
                let prev = runningStreaks[winner] ?? 0
                if prev >= 0 {
                    runningStreaks[winner] = prev + 1
                } else {
                    runningStreaks[winner] = 1
                }
                bestWinStreaks[winner] = max(bestWinStreaks[winner] ?? 0, runningStreaks[winner]!)
            }
            
            for loser in losers {
                playerStatsMap[loser]?.losses += 1
                playerStatsMap[loser]?.pointDiff -= (game.winnerScore - game.loserScore)
                
                // Update running streak for worst streak calculation
                let prev = runningStreaks[loser] ?? 0
                if prev <= 0 {
                    runningStreaks[loser] = prev - 1
                } else {
                    runningStreaks[loser] = -1
                }
                worstLoseStreaks[loser] = max(worstLoseStreaks[loser] ?? 0, abs(runningStreaks[loser]!))
            }
            
            // Update team stats
            let winningTeamKey = TeamStats.makeKey(p1: game.winner1, p2: game.winner2)
            let losingTeamKey = TeamStats.makeKey(p1: game.loser1, p2: game.loser2)
            
            if teamStatsMap[winningTeamKey] == nil {
                teamStatsMap[winningTeamKey] = TeamStats(player1: game.winner1, player2: game.winner2)
            }
            teamStatsMap[winningTeamKey]?.wins += 1
            
            if teamStatsMap[losingTeamKey] == nil {
                teamStatsMap[losingTeamKey] = TeamStats(player1: game.loser1, player2: game.loser2)
            }
            teamStatsMap[losingTeamKey]?.losses += 1
            
            // Monthly activity
            let gameYear = calendar.component(.year, from: game.date)
            let month = calendar.component(.month, from: game.date)
            let monthKey = "\(gameYear)-\(month)"
            if monthlyMap[monthKey] == nil {
                monthlyMap[monthKey] = MonthlyActivity(year: gameYear, month: month, gameCount: 0)
            }
            monthlyMap[monthKey]?.gameCount += 1
        }
        
        // Apply best/worst streaks for the period
        for (name, streak) in bestWinStreaks {
            playerStatsMap[name]?.bestWinStreak = streak
        }
        for (name, streak) in worstLoseStreaks {
            playerStatsMap[name]?.worstLoseStreak = streak
        }
        
        // Calculate CURRENT streaks from most recent games (looking backward from latest)
        // This uses all games to determine current streak status
        let gamesForCurrentStreak = allGamesForStreaks ?? games
        let currentStreaks = calculateCurrentStreaks(from: gamesForCurrentStreak, forPlayers: Set(playerStatsMap.keys))
        
        for (name, streak) in currentStreaks {
            playerStatsMap[name]?.currentStreak = streak
        }
        
        // Calculate TrueSkill ratings for the filtered period
        let trueSkillRatings = TrueSkillRatingSystem.calculateRatings(from: filteredGames)
        
        for (name, rating) in trueSkillRatings {
            playerStatsMap[name]?.trueSkillMu = rating.mu
            playerStatsMap[name]?.trueSkillSigma = rating.sigma
            playerStatsMap[name]?.trueSkillExposed = rating.exposed
        }
        
        // Today's stats (always from full games list so the card shows when there are games today, regardless of year filter)
        let today = calendar.startOfDay(for: Date())
        let todayGames = games.filter { calendar.startOfDay(for: $0.date) == today }
        var todayStats: DayStats? = nil
        
        if !todayGames.isEmpty {
            var todayPlayerMap: [String: PlayerStats] = [:]
            
            for game in todayGames {
                for winner in [game.winner1, game.winner2] {
                    if todayPlayerMap[winner] == nil {
                        todayPlayerMap[winner] = PlayerStats(name: winner)
                    }
                    todayPlayerMap[winner]?.wins += 1
                    todayPlayerMap[winner]?.pointDiff += (game.winnerScore - game.loserScore)
                }
                for loser in [game.loser1, game.loser2] {
                    if todayPlayerMap[loser] == nil {
                        todayPlayerMap[loser] = PlayerStats(name: loser)
                    }
                    todayPlayerMap[loser]?.losses += 1
                    todayPlayerMap[loser]?.pointDiff -= (game.winnerScore - game.loserScore)
                }
            }
            
            todayStats = DayStats(
                date: today,
                players: todayPlayerMap.values.sorted { 
                    if $0.winRate != $1.winRate {
                        return $0.winRate > $1.winRate
                    }
                    return $0.pointDiff > $1.pointDiff
                }
            )
        }
        
        let players = Array(playerStatsMap.values)
        let teams = Array(teamStatsMap.values)
        let monthly = monthlyMap.values.sorted { 
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.month > $1.month
        }
        
        return (players, teams, todayStats, monthly)
    }
    
    /// Calculate current streaks by looking at most recent games for each player
    /// A player's current streak is determined by their most recent consecutive wins or losses
    private static func calculateCurrentStreaks(from games: [LegacyGame], forPlayers players: Set<String>) -> [String: Int] {
        var streaks: [String: Int] = [:]
        
        // Sort games newest first
        let sortedGames = games.sorted { $0.date > $1.date }
        
        // Track which players we've already determined streak for
        var determined: Set<String> = []
        
        for game in sortedGames {
            let winners = Set([game.winner1, game.winner2])
            let losers = Set([game.loser1, game.loser2])
            let gamePlayers = winners.union(losers)
            
            for player in gamePlayers {
                guard players.contains(player), !determined.contains(player) else { continue }
                
                let isWinner = winners.contains(player)
                let currentStreak = streaks[player] ?? 0
                
                if currentStreak == 0 {
                    // First game we're seeing for this player (their most recent)
                    streaks[player] = isWinner ? 1 : -1
                } else if (currentStreak > 0 && isWinner) {
                    // Continuing a winning streak
                    streaks[player] = currentStreak + 1
                } else if (currentStreak < 0 && !isWinner) {
                    // Continuing a losing streak
                    streaks[player] = currentStreak - 1
                } else {
                    // Streak ended - this player's current streak is determined
                    determined.insert(player)
                }
            }
            
            // Stop if we've determined all players
            if determined.count == players.count {
                break
            }
        }
        
        return streaks
    }
}
