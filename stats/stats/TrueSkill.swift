import Foundation

// MARK: - TrueSkill Implementation
// Based on Microsoft's TrueSkill algorithm and Python trueskill library defaults
// Reference: https://trueskill.org/ and https://github.com/sublee/trueskill

/// Gaussian distribution representing a player's skill
struct Gaussian {
    var mu: Double      // Mean (skill estimate)
    var sigma: Double   // Standard deviation (uncertainty)
    
    /// Precision (inverse of variance)
    var precision: Double { 1.0 / (sigma * sigma) }
    
    /// Precision-adjusted mean
    var precisionMean: Double { mu / (sigma * sigma) }
    
    init(mu: Double = 25.0, sigma: Double = 25.0 / 3.0) {
        self.mu = mu
        self.sigma = sigma
    }
    
    /// Create from precision form
    static func fromPrecision(precisionMean: Double, precision: Double) -> Gaussian {
        let sigma = sqrt(1.0 / precision)
        let mu = precisionMean / precision
        return Gaussian(mu: mu, sigma: sigma)
    }
    
    /// Multiply two Gaussians
    static func * (lhs: Gaussian, rhs: Gaussian) -> Gaussian {
        let precision = lhs.precision + rhs.precision
        let precisionMean = lhs.precisionMean + rhs.precisionMean
        return Gaussian.fromPrecision(precisionMean: precisionMean, precision: precision)
    }
    
    /// Divide two Gaussians
    static func / (lhs: Gaussian, rhs: Gaussian) -> Gaussian {
        let precision = lhs.precision - rhs.precision
        let precisionMean = lhs.precisionMean - rhs.precisionMean
        return Gaussian.fromPrecision(precisionMean: precisionMean, precision: precision)
    }
}

// MARK: - TrueSkill Environment

final class TrueSkillEnv {
    // Default parameters matching Python trueskill library
    let mu: Double = 25.0                    // Initial mean
    let sigma: Double = 25.0 / 3.0           // Initial sigma (~8.333)
    let beta: Double = 25.0 / 6.0            // Performance variance (~4.167)
    let tau: Double = 25.0 / 300.0           // Dynamics factor (~0.0833)
    let drawProbability: Double = 0.0        // No draws in volleyball
    
    static let shared = TrueSkillEnv()
    
    /// Create a new rating with default values
    func createRating() -> Gaussian {
        Gaussian(mu: mu, sigma: sigma)
    }
    
    /// Calculate the conservative skill estimate (what's displayed)
    /// This is μ - 3σ, representing ~99% confidence lower bound
    func expose(_ rating: Gaussian) -> Double {
        rating.mu - 3.0 * rating.sigma
    }
    
    /// Rate a 2v2 match
    /// - Parameters:
    ///   - winners: Tuple of two winner ratings
    ///   - losers: Tuple of two loser ratings
    /// - Returns: Updated ratings for all four players
    func rate2v2(
        winners: (Gaussian, Gaussian),
        losers: (Gaussian, Gaussian)
    ) -> (winners: (Gaussian, Gaussian), losers: (Gaussian, Gaussian)) {
        // Calculate team performances
        let winnerMu = winners.0.mu + winners.1.mu
        let loserMu = losers.0.mu + losers.1.mu
        
        let winnerSigmaSq = winners.0.sigma * winners.0.sigma + 
                           winners.1.sigma * winners.1.sigma +
                           2 * beta * beta
        let loserSigmaSq = losers.0.sigma * losers.0.sigma + 
                          losers.1.sigma * losers.1.sigma +
                          2 * beta * beta
        
        // Total variance
        let c = sqrt(winnerSigmaSq + loserSigmaSq)
        
        // Performance difference
        let deltaMu = winnerMu - loserMu
        
        // Calculate v and w functions (truncated Gaussian moments)
        let t = deltaMu / c
        let v = vFunc(t: t, epsilon: 0)
        let w = wFunc(t: t, epsilon: 0)
        
        // Update winner ratings
        let winner1NewMu = winners.0.mu + (winners.0.sigma * winners.0.sigma / c) * v
        let winner2NewMu = winners.1.mu + (winners.1.sigma * winners.1.sigma / c) * v
        
        let winner1NewSigma = winners.0.sigma * sqrt(1 - (winners.0.sigma * winners.0.sigma / (c * c)) * w)
        let winner2NewSigma = winners.1.sigma * sqrt(1 - (winners.1.sigma * winners.1.sigma / (c * c)) * w)
        
        // Update loser ratings
        let loser1NewMu = losers.0.mu - (losers.0.sigma * losers.0.sigma / c) * v
        let loser2NewMu = losers.1.mu - (losers.1.sigma * losers.1.sigma / c) * v
        
        let loser1NewSigma = losers.0.sigma * sqrt(1 - (losers.0.sigma * losers.0.sigma / (c * c)) * w)
        let loser2NewSigma = losers.1.sigma * sqrt(1 - (losers.1.sigma * losers.1.sigma / (c * c)) * w)
        
        // Apply dynamics (tau) - skill can change over time
        let applyTau = { (sigma: Double) -> Double in
            sqrt(sigma * sigma + self.tau * self.tau)
        }
        
        return (
            winners: (
                Gaussian(mu: winner1NewMu, sigma: applyTau(winner1NewSigma)),
                Gaussian(mu: winner2NewMu, sigma: applyTau(winner2NewSigma))
            ),
            losers: (
                Gaussian(mu: loser1NewMu, sigma: applyTau(loser1NewSigma)),
                Gaussian(mu: loser2NewMu, sigma: applyTau(loser2NewSigma))
            )
        )
    }
    
    // MARK: - Helper Functions (Truncated Gaussian)
    
    /// Standard normal PDF
    private func pdf(_ x: Double) -> Double {
        return exp(-0.5 * x * x) / sqrt(2 * .pi)
    }
    
    /// Standard normal CDF (approximation)
    private func cdf(_ x: Double) -> Double {
        // Using error function approximation
        let t = 1.0 / (1.0 + 0.2316419 * abs(x))
        let d = 0.3989422804014327 // 1/sqrt(2*pi)
        let p = d * exp(-x * x / 2.0) * 
                (0.319381530 * t - 
                 0.356563782 * t * t + 
                 1.781477937 * t * t * t - 
                 1.821255978 * t * t * t * t + 
                 1.330274429 * t * t * t * t * t)
        return x >= 0 ? 1.0 - p : p
    }
    
    /// V function for TrueSkill (truncated Gaussian first moment)
    private func vFunc(t: Double, epsilon: Double) -> Double {
        let denom = cdf(t - epsilon)
        if denom < 1e-10 {
            return -t + epsilon
        }
        return pdf(t - epsilon) / denom
    }
    
    /// W function for TrueSkill (truncated Gaussian second moment adjustment)
    private func wFunc(t: Double, epsilon: Double) -> Double {
        let v = vFunc(t: t, epsilon: epsilon)
        return v * (v + t - epsilon)
    }
}

// MARK: - TrueSkill Rating System

final class TrueSkillRatingSystem {
    private let env = TrueSkillEnv.shared
    private var ratings: [String: Gaussian] = [:]
    
    /// Get or create rating for a player
    func rating(for player: String) -> Gaussian {
        if let existing = ratings[player] {
            return existing
        }
        let newRating = env.createRating()
        ratings[player] = newRating
        return newRating
    }
    
    /// Update rating for a player
    func setRating(_ rating: Gaussian, for player: String) {
        ratings[player] = rating
    }
    
    /// Get the displayed skill value (mu - 3*sigma)
    func exposedRating(for player: String) -> Double {
        let r = rating(for: player)
        return env.expose(r)
    }
    
    /// Get mu value
    func mu(for player: String) -> Double {
        rating(for: player).mu
    }
    
    /// Get sigma value
    func sigma(for player: String) -> Double {
        rating(for: player).sigma
    }
    
    /// Process a single 2v2 game result
    func processGame(
        winner1: String,
        winner2: String,
        loser1: String,
        loser2: String
    ) {
        let w1Rating = rating(for: winner1)
        let w2Rating = rating(for: winner2)
        let l1Rating = rating(for: loser1)
        let l2Rating = rating(for: loser2)
        
        let result = env.rate2v2(
            winners: (w1Rating, w2Rating),
            losers: (l1Rating, l2Rating)
        )
        
        setRating(result.winners.0, for: winner1)
        setRating(result.winners.1, for: winner2)
        setRating(result.losers.0, for: loser1)
        setRating(result.losers.1, for: loser2)
    }
    
    /// Process all games and return final ratings
    /// Games should be sorted chronologically (oldest first)
    static func calculateRatings(from games: [LegacyGame]) -> [String: (mu: Double, sigma: Double, exposed: Double)] {
        let system = TrueSkillRatingSystem()
        
        // Process games in chronological order (oldest to newest)
        let sortedGames = games.sorted { $0.date < $1.date }
        
        for game in sortedGames {
            system.processGame(
                winner1: game.winner1,
                winner2: game.winner2,
                loser1: game.loser1,
                loser2: game.loser2
            )
        }
        
        // Collect all player ratings
        var results: [String: (mu: Double, sigma: Double, exposed: Double)] = [:]
        
        let allPlayers = Set(games.flatMap { [$0.winner1, $0.winner2, $0.loser1, $0.loser2] })
        
        for player in allPlayers {
            let r = system.rating(for: player)
            results[player] = (
                mu: r.mu,
                sigma: r.sigma,
                exposed: TrueSkillEnv.shared.expose(r)
            )
        }
        
        return results
    }
}
