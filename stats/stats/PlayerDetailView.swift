import SwiftUI

struct PlayerDetailView: View {
    let playerName: String
    let games: [LegacyGame]
    var cloudDbId: String? = nil

    @State private var fetchedPlayerGames: [LegacyGame]? = nil

    private var playerGames: [LegacyGame] {
        if let fetched = fetchedPlayerGames {
            return fetched
        }
        return games.filter { game in
            [game.winner1, game.winner2, game.loser1, game.loser2].contains(playerName)
        }
    }
    
    private var wins: Int {
        playerGames.filter { game in
            game.winner1 == playerName || game.winner2 == playerName
        }.count
    }
    
    private var losses: Int {
        playerGames.filter { game in
            game.loser1 == playerName || game.loser2 == playerName
        }.count
    }
    
    private var totalGames: Int { wins + losses }
    private var winRate: Double { totalGames > 0 ? Double(wins) / Double(totalGames) * 100 : 0 }
    
    private var trueSkill: Double {
        let gamesForSkill = playerGames.filter { game in
            let w1 = game.winner1.trimmingCharacters(in: .whitespaces)
            let w2 = game.winner2.trimmingCharacters(in: .whitespaces)
            let l1 = game.loser1.trimmingCharacters(in: .whitespaces)
            let l2 = game.loser2.trimmingCharacters(in: .whitespaces)
            return !w1.isEmpty && !w2.isEmpty && !l1.isEmpty && !l2.isEmpty
        }
        let ratings = TrueSkillRatingSystem.calculateRatings(from: gamesForSkill)
        return ratings[playerName]?.exposed ?? 0
    }
    
    /// (partner name, wins, losses) when this player teamed with that partner
    private var partnerStats: [(name: String, wins: Int, losses: Int)] {
        var withPartner: [String: (wins: Int, losses: Int)] = [:]
        for game in playerGames {
            let teammate: String
            let weWon: Bool
            if game.winner1 == playerName {
                teammate = game.winner2
                weWon = true
            } else if game.winner2 == playerName {
                teammate = game.winner1
                weWon = true
            } else if game.loser1 == playerName {
                teammate = game.loser2
                weWon = false
            } else {
                teammate = game.loser1
                weWon = false
            }
            let key = teammate.trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            var cur = withPartner[key] ?? (0, 0)
            if weWon { cur.wins += 1 } else { cur.losses += 1 }
            withPartner[key] = cur
        }
        return withPartner.map { (name: $0.key, wins: $0.value.wins, losses: $0.value.losses) }
            .sorted { p1, p2 in
                let t1 = p1.wins + p1.losses
                let t2 = p2.wins + p2.losses
                let rate1 = t1 > 0 ? Double(p1.wins) / Double(t1) : 0
                let rate2 = t2 > 0 ? Double(p2.wins) / Double(t2) : 0
                if rate1 != rate2 { return rate1 > rate2 }
                return t1 > t2
            }
    }
    
    /// (opponent name, wins, losses) — games where this player's team faced a team containing that opponent
    private var versusStats: [(name: String, wins: Int, losses: Int)] {
        var vsOpponent: [String: (wins: Int, losses: Int)] = [:]
        for game in playerGames {
            let weWon: Bool
            let opponents: [String]
            if game.winner1 == playerName || game.winner2 == playerName {
                weWon = true
                opponents = [game.loser1, game.loser2]
            } else {
                weWon = false
                opponents = [game.winner1, game.winner2]
            }
            for opp in opponents {
                let key = opp.trimmingCharacters(in: .whitespaces)
                if key.isEmpty { continue }
                var cur = vsOpponent[key] ?? (0, 0)
                if weWon { cur.wins += 1 } else { cur.losses += 1 }
                vsOpponent[key] = cur
            }
        }
        return vsOpponent.map { (name: $0.key, wins: $0.value.wins, losses: $0.value.losses) }
            .sorted { v1, v2 in
                let t1 = v1.wins + v1.losses
                let t2 = v2.wins + v2.losses
                let rate1 = t1 > 0 ? Double(v1.wins) / Double(t1) : 0
                let rate2 = t2 > 0 ? Double(v2.wins) / Double(t2) : 0
                if rate1 != rate2 { return rate1 > rate2 }
                return t1 > t2
            }
    }
    
    private var isLoadingFromCloud: Bool {
        cloudDbId != nil && fetchedPlayerGames == nil
    }

    var body: some View {
        Group {
            if isLoadingFromCloud {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        overallSection
                        withPartnersSection
                        versusSection
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.1, blue: 0.16),
                    Color(red: 0.1, green: 0.14, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(playerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
        .task {
            guard let dbId = cloudDbId, fetchedPlayerGames == nil else { return }
            cloud.fetchGamesForPlayer(dbId: dbId, playerName: playerName) { result in
                if case .success(let list) = result {
                    fetchedPlayerGames = list
                }
            }
        }
    }
    
    private var overallSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            
            HStack(spacing: 16) {
                miniStat(value: "\(wins)-\(losses)", label: "Record")
                miniStat(value: String(format: "%.0f%%", winRate), label: "Win%")
                miniStat(value: "\(totalGames)", label: "Games")
                miniStat(value: String(format: "%.1f", trueSkill), label: "Skill")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var withPartnersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("With partner")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            
            if partnerStats.isEmpty {
                Text("No partner data")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(partnerStats, id: \.name) { p in
                        HStack {
                            Text(p.name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(p.wins)-\(p.losses)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            if p.wins + p.losses > 0 {
                                Text(String(format: "%.0f%%", Double(p.wins) / Double(p.wins + p.losses) * 100))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.05))
                        
                        if p.name != partnerStats.last?.name {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.leading, 14)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var versusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record vs")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            
            if versusStats.isEmpty {
                Text("No head-to-head data")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(versusStats, id: \.name) { v in
                        HStack {
                            Text(v.name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(v.wins)-\(v.losses)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            if v.wins + v.losses > 0 {
                                Text(String(format: "%.0f%%", Double(v.wins) / Double(v.wins + v.losses) * 100))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.05))
                        
                        if v.name != versusStats.last?.name {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.leading, 14)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        PlayerDetailView(
            playerName: "Player",
            games: []
        )
    }
}
