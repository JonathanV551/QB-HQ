import Foundation
import Combine

@MainActor
final class QBViewModel: ObservableObject {
    @Published private(set) var quarterbacks: [Quarterback] = []
    @Published private(set) var teamStats: [TeamStats] = []
    @Published var lastUpdated: Date?

    func loadQuarterbacks() async {
        do {
            let qbs = try await NetworkManager.shared.fetchQuarterbacks()
            // Optionally you may want to sort or filter the results here
            self.quarterbacks = qbs
            self.lastUpdated = Date()
        } catch {
            print("Failed fetching QBs: \(error)")
            self.quarterbacks = []
        }
    }

    func loadTeamStats() async {
        do {
            let teams = try await NetworkManager.shared.fetchTeamStats()
            self.teamStats = teams
            self.lastUpdated = Date()
        } catch {
            print("Failed fetching team stats: \(error)")
            self.teamStats = []
        }
    }

    struct MatchupPrediction {
        let predictedPassingYards: Double?
        let predictedPassingTDs: Double?
        let summary: String
    }

    func predictMatchup(for qb: Quarterback, against opponent: TeamStats) -> MatchupPrediction {
        // Helper to find a key in team stats matching certain substrings
        func findKey(containing parts: [String]) -> String? {
            for key in opponent.stats.keys {
                let lower = key.lowercased()
                var matched = true
                for p in parts {
                    if !lower.contains(p) { matched = false; break }
                }
                if matched { return key }
            }
            return nil
        }

        func leagueAverage(for key: String) -> Double? {
            let values = teamStats.compactMap { $0.stats[key] }
            guard !values.isEmpty else { return nil }
            return values.reduce(0.0, +) / Double(values.count)
        }

        // Keys to consider
        let passYardsKey = findKey(containing: ["pass", "yd"]) ?? findKey(containing: ["pass", "yard"]) ?? findKey(containing: ["pass"])
        let completionKey = findKey(containing: ["comp"]) ?? findKey(containing: ["completion"]) ?? findKey(containing: ["pct"]) // completion %
        let sackKey = findKey(containing: ["sack"])
        let intKey = findKey(containing: ["int"]) ?? findKey(containing: ["intercept"]) // interceptions forced
        let passTdKey = findKey(containing: ["pass", "td"]) ?? findKey(containing: ["pass", "tds"]) ?? findKey(containing: ["pass", "touchdown"])

        // Build weighted factors - lower factor means defense reduces expected output
        var weighted: [(factor: Double, weight: Double)] = []

        if let key = passYardsKey, let teamVal = opponent.stats[key], let league = leagueAverage(for: key), league > 0 {
            let factor = teamVal / league
            weighted.append((factor, 0.6))
        }

        if let key = completionKey, let teamVal = opponent.stats[key], let league = leagueAverage(for: key), league > 0 {
            let factor = teamVal / league
            weighted.append((factor, 0.2))
        }

        if let key = sackKey, let teamVal = opponent.stats[key], let league = leagueAverage(for: key), teamVal > 0 {
            // More sacks -> better rush -> lower expected passing output
            let factor = league / teamVal
            weighted.append((factor, 0.1))
        }

        if let key = intKey, let teamVal = opponent.stats[key], let league = leagueAverage(for: key), teamVal > 0 {
            // More interceptions forced is good for defense
            let factor = league / teamVal
            weighted.append((factor, 0.1))
        }

        guard !weighted.isEmpty else {
            return MatchupPrediction(predictedPassingYards: nil, predictedPassingTDs: nil, summary: "Not enough defensive metrics available to generate a matchup prediction.")
        }

        let (weightedSum, weightSum) = weighted.reduce((0.0, 0.0)) { acc, item in
            (acc.0 + item.factor * item.weight, acc.1 + item.weight)
        }
        let finalFactor = weightSum > 0 ? (weightedSum / weightSum) : 1.0

        var summaryParts: [String] = []
        if let qbYards = qb.passingYards.map(Double.init) {
            let predictedY = qbYards * finalFactor
            let pct = qbYards > 0 ? ((predictedY - qbYards) / qbYards * 100.0) : 0.0
            summaryParts.append(String(format: "Passing yards ~ %.0f (%.0f%% vs current).", predictedY, pct))
        }

        var predictedTDs: Double? = nil
        if let qbTDs = qb.touchdowns.map(Double.init) {
            // Use same factor for TDs if specific TD metric is not available
            if let tdKey = passTdKey, let teamTd = opponent.stats[tdKey], let leagueTd = leagueAverage(for: tdKey), leagueTd > 0 {
                let factorTd = teamTd / leagueTd
                predictedTDs = qbTDs * factorTd
            } else {
                predictedTDs = qbTDs * finalFactor
            }
            summaryParts.append(String(format: "Passing TDs ~ %.1f.", predictedTDs ?? 0))
        }

        // Add some context about which metrics were used
        var usedMetrics: [String] = []
        if passYardsKey != nil { usedMetrics.append("pass yards") }
        if completionKey != nil { usedMetrics.append("completion pct") }
        if sackKey != nil { usedMetrics.append("sacks") }
        if intKey != nil { usedMetrics.append("ints") }

        let context = "Based on team defense metrics (" + usedMetrics.joined(separator: ", ") + ")."
        let fullSummary = (summaryParts + [context]).joined(separator: " ")

        return MatchupPrediction(predictedPassingYards: qb.passingYards.map(Double.init).map { $0 * finalFactor }, predictedPassingTDs: predictedTDs, summary: fullSummary)
    }

    /// Returns the available week numbers for a given team (sorted ascending)
    func weeks(for teamName: String) -> [Int] {
        let weeks = teamStats.compactMap { ts in
            ts.team == teamName ? ts.week : nil
        }
        return Array(Set(weeks)).sorted()
    }

    /// Aggregate a team's stats (average) across weeks up to `throughWeek`. If `throughWeek` is nil, average across all available weeks.
    func aggregatedStats(for teamName: String, throughWeek: Int?) -> [String: Double] {
        let entries = teamStats.filter { ts in
            guard ts.team == teamName else { return false }
            if let w = throughWeek { return (ts.week ?? Int.max) <= w }
            return true
        }
        guard !entries.isEmpty else { return [:] }

        var agg: [String: Double] = [:]
        let allKeys = Set(entries.flatMap { $0.stats.keys })
        for key in allKeys {
            let values = entries.compactMap { $0.stats[key] }
            guard !values.isEmpty else { continue }
            agg[key] = values.reduce(0.0, +) / Double(values.count)
        }
        return agg
    }

    /// Compute a league average for a specific key across teams, using aggregated stats through the same week if provided.
    func leagueAverage(for key: String, throughWeek: Int?) -> Double? {
        let teamNames = Set(teamStats.map { $0.team })
        var values: [Double] = []
        for team in teamNames {
            let agg = aggregatedStats(for: team, throughWeek: throughWeek)
            if let v = agg[key] { values.append(v) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }

    /// Predict a matchup using a team's aggregated defensive data through a specific week (or full season if week == nil)
    func predictMatchup(for qb: Quarterback, againstTeamName teamName: String, throughWeek: Int?) -> MatchupPrediction {
        let opponentAgg = aggregatedStats(for: teamName, throughWeek: throughWeek)
        guard !opponentAgg.isEmpty else {
            return MatchupPrediction(predictedPassingYards: nil, predictedPassingTDs: nil, summary: "No team defensive data available for that team/week range.")
        }

        func findKey(in dict: [String: Double], containing parts: [String]) -> String? {
            for key in dict.keys {
                let lower = key.lowercased()
                var matched = true
                for p in parts { if !lower.contains(p) { matched = false; break } }
                if matched { return key }
            }
            return nil
        }

        // Attempt to locate useful keys in the aggregated data
        let passYardsKey = findKey(in: opponentAgg, containing: ["pass", "yd"]) ?? findKey(in: opponentAgg, containing: ["pass", "yard"]) ?? findKey(in: opponentAgg, containing: ["pass"])
        let completionKey = findKey(in: opponentAgg, containing: ["comp"]) ?? findKey(in: opponentAgg, containing: ["completion"]) ?? findKey(in: opponentAgg, containing: ["pct"])
        let sackKey = findKey(in: opponentAgg, containing: ["sack"])
        let intKey = findKey(in: opponentAgg, containing: ["int"]) ?? findKey(in: opponentAgg, containing: ["intercept"]) // interceptions forced
        let passTdKey = findKey(in: opponentAgg, containing: ["pass", "td"]) ?? findKey(in: opponentAgg, containing: ["pass", "tds"]) ?? findKey(in: opponentAgg, containing: ["pass", "touchdown"])

        var weighted: [(factor: Double, weight: Double)] = []

        if let key = passYardsKey, let teamVal = opponentAgg[key], let league = leagueAverage(for: key, throughWeek: throughWeek), league > 0 {
            let factor = teamVal / league
            weighted.append((factor, 0.6))
        }
        if let key = completionKey, let teamVal = opponentAgg[key], let league = leagueAverage(for: key, throughWeek: throughWeek), league > 0 {
            let factor = teamVal / league
            weighted.append((factor, 0.2))
        }
        if let key = sackKey, let teamVal = opponentAgg[key], let league = leagueAverage(for: key, throughWeek: throughWeek), teamVal > 0 {
            let factor = league / teamVal
            weighted.append((factor, 0.1))
        }
        if let key = intKey, let teamVal = opponentAgg[key], let league = leagueAverage(for: key, throughWeek: throughWeek), teamVal > 0 {
            let factor = league / teamVal
            weighted.append((factor, 0.1))
        }

        guard !weighted.isEmpty else {
            return MatchupPrediction(predictedPassingYards: nil, predictedPassingTDs: nil, summary: "Not enough defensive metrics available to generate a matchup prediction.")
        }

        let (weightedSum, weightSum) = weighted.reduce((0.0, 0.0)) { acc, item in
            (acc.0 + item.factor * item.weight, acc.1 + item.weight)
        }
        let finalFactor = weightSum > 0 ? (weightedSum / weightSum) : 1.0

        // compute how many weeks we're using for the opponent
        let consideredEntries = teamStats.filter { ts in
            ts.team == teamName && (throughWeek == nil || (ts.week ?? Int.max) <= throughWeek!)
        }
        let weeksCount = max(1, consideredEntries.count)

        var summaryParts: [String] = []
        if let qbYards = qb.passingYards.map(Double.init) {
            // compute QB per-week average (approximate) and predict per-game output
            let qbYardsPerWeek = qbYards / Double(max(1, weeksCount))
            let predictedPerGame = qbYardsPerWeek * finalFactor
            let pct = qbYardsPerWeek > 0 ? ((predictedPerGame - qbYardsPerWeek) / qbYardsPerWeek * 100.0) : 0.0
            summaryParts.append(String(format: "Passing yards (game) ~ %.0f (%.0f%% vs QB per-week avg %.0f).", predictedPerGame, pct, qbYardsPerWeek))
        }

        var predictedTDs: Double? = nil
        if let qbTDs = qb.touchdowns.map(Double.init) {
            // compute per-week TD average and predict per-game TDs
            let qbTDsPerWeek = qbTDs / Double(max(1, weeksCount))
            if let tdKey = passTdKey, let teamTd = opponentAgg[tdKey], let leagueTd = leagueAverage(for: tdKey, throughWeek: throughWeek), leagueTd > 0 {
                let factorTd = teamTd / leagueTd
                predictedTDs = qbTDsPerWeek * factorTd
            } else {
                predictedTDs = qbTDsPerWeek * finalFactor
            }
            summaryParts.append(String(format: "Passing TDs (game) ~ %.1f.", predictedTDs ?? 0))
        }

        let used = [passYardsKey, completionKey, sackKey, intKey].compactMap { $0 }.map { $0 } // used metric keys
        let weekText = throughWeek.map { String($0) } ?? "All"
        let context = "Using aggregated team defense through week \(weekText) with metrics: " + (used.isEmpty ? "none" : used.joined(separator: ", "))
        let fullSummary = (summaryParts + [context]).joined(separator: " ")

        let predictedYPerGame: Double? = {
            guard let qbYards = qb.passingYards.map(Double.init) else { return nil }
            let qbYardsPerWeek = qbYards / Double(max(1, weeksCount))
            return qbYardsPerWeek * finalFactor
        }()

        return MatchupPrediction(predictedPassingYards: predictedYPerGame, predictedPassingTDs: predictedTDs, summary: fullSummary)
    }
}
