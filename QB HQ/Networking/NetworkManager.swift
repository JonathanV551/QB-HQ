import Foundation

final class NetworkManager {
    static let shared = NetworkManager()
    private init() {}

    private let csvURLString = "https://raw.githubusercontent.com/hvpkod/NFL-Data/refs/heads/main/NFL-data-Players/2025/QB_season.csv"
    private let teamStatsURLString = "https://github.com/nflverse/nflverse-data/releases/download/stats_team/stats_team_week_2025.csv"

    /// Fetches the raw CSV from GitHub and returns an array of parsed `Quarterback` objects.
    /// Uses async/await for networking.
    func fetchQuarterbacks() async throws -> [Quarterback] {
        guard let url = URL(string: csvURLString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let csvString = String(data: data, encoding: .utf8) else { return [] }
        return parseCSV(csvString)
    }

    /// Fetches the team defensive stats from GitHub and returns an array of parsed `TeamStats` objects.
    /// Uses async/await for networking.
    func fetchTeamStats() async throws -> [TeamStats] {
        guard let url = URL(string: teamStatsURLString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let csvString = String(data: data, encoding: .utf8) else { return [] }
        return parseTeamCSV(csvString)
    }

    /// Very small CSV parser intended for this CSV file.
    /// - Strategy:
    ///   - Split the file by newlines
    ///   - Re-assemble records that were accidentally split across lines (the dataset has names split across lines)
    ///   - Split a completed record by commas and map the known columns
    private func parseCSV(_ csv: String) -> [Quarterback] {
        var qbs: [Quarterback] = []

        let lines = csv.components(separatedBy: CharacterSet.newlines)
        guard lines.count > 1 else { return qbs }

        let header = lines[0]
        let expectedColumns = header.components(separatedBy: ",").count

        var index = 1
        while index < lines.count {
            var line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                index += 1
                continue
            }

            // If the line doesn't have enough columns, it was likely split because the player's name
            // contains a newline. Keep joining lines until we have at least the expected number of columns.
            var columnCount = line.components(separatedBy: ",").count
            while columnCount < expectedColumns && index + 1 < lines.count {
                index += 1
                let next = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if next.isEmpty { continue }
                line += " " + next
                columnCount = line.components(separatedBy: ",").count
            }

            let cols = line.components(separatedBy: ",")
            if cols.count >= expectedColumns {
                let name = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let playerId = cols.count > 1 ? cols[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let id = (playerId?.isEmpty == false) ? playerId! : UUID().uuidString
                let team = cols.count > 3 ? cols[3].trimmingCharacters(in: .whitespacesAndNewlines) : nil

                let passingYards = Int(cols.count > 4 ? cols[4].trimmingCharacters(in: .whitespacesAndNewlines) : "")
                let touchdowns = Int(cols.count > 5 ? cols[5].trimmingCharacters(in: .whitespacesAndNewlines) : "")
                let interceptions = Int(cols.count > 6 ? cols[6].trimmingCharacters(in: .whitespacesAndNewlines) : "")

                let rushingYards = Int(cols.count > 7 ? cols[7].trimmingCharacters(in: .whitespacesAndNewlines) : "")
                let rushingTD = Int(cols.count > 8 ? cols[8].trimmingCharacters(in: .whitespacesAndNewlines) : "")

                let receivingRec = Int(cols.count > 9 ? cols[9].trimmingCharacters(in: .whitespacesAndNewlines) : "")
                let receivingYards = Int(cols.count > 10 ? cols[10].trimmingCharacters(in: .whitespacesAndNewlines) : "")
                let receivingTD = Int(cols.count > 11 ? cols[11].trimmingCharacters(in: .whitespacesAndNewlines) : "")

                let rank = Int(cols.count > 26 ? cols[26].trimmingCharacters(in: .whitespacesAndNewlines) : "")
                let totalPoints = Double(cols.count > 27 ? cols[27].trimmingCharacters(in: .whitespacesAndNewlines) : "")

                // The provided CSV still does not include completions, attempts or passer rating in this dataset.
                let qb = Quarterback(
                    id: id,
                    name: name,
                    playerId: playerId,
                    team: team,
                    completions: nil,
                    attempts: nil,
                    passingYards: passingYards,
                    touchdowns: touchdowns,
                    interceptions: interceptions,
                    passerRating: nil,
                    rushingYards: rushingYards,
                    rushingTouchdowns: rushingTD,
                    receivingReceptions: receivingRec,
                    receivingYards: receivingYards,
                    receivingTouchdowns: receivingTD,
                    rank: rank,
                    totalPoints: totalPoints
                )
                qbs.append(qb)
            }

            index += 1
        }

        return qbs
    }

    private func parseTeamCSV(_ csv: String) -> [TeamStats] {
        var teams: [TeamStats] = []

        let lines = csv.components(separatedBy: CharacterSet.newlines)
        guard lines.count > 1 else { return teams }

        let header = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let expectedColumns = header.count

        var index = 1
        while index < lines.count {
            var line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                index += 1
                continue
            }

            var columnCount = line.components(separatedBy: ",").count
            while columnCount < expectedColumns && index + 1 < lines.count {
                index += 1
                let next = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if next.isEmpty { continue }
                line += " " + next
                columnCount = line.components(separatedBy: ",").count
            }

            let cols = line.components(separatedBy: ",")
            if cols.count >= expectedColumns {
                // find the team column
                let teamIndex = header.firstIndex(where: { $0.lowercased().contains("team") }) ?? 0
                let teamName = cols.count > teamIndex ? cols[teamIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""

                // find week column if present
                let weekIndex = header.firstIndex(where: { $0.lowercased().contains("week") })
                var week: Int? = nil
                if let wIndex = weekIndex, cols.count > wIndex {
                    week = Int(cols[wIndex].trimmingCharacters(in: .whitespacesAndNewlines))
                }

                var stats: [String: Double] = [:]

                for (i, key) in header.enumerated() {
                    let raw = cols.count > i ? cols[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    let cleaned = raw.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: "")
                    if let d = Double(cleaned) {
                        stats[key.lowercased()] = d
                    }
                }

                let id: String
                if let w = week {
                    id = "\(teamName)-w\(w)"
                } else {
                    id = teamName.isEmpty ? UUID().uuidString : teamName
                }
                teams.append(TeamStats(id: id, team: teamName, week: week, stats: stats))
            }

            index += 1
        }

        return teams
    }
}
