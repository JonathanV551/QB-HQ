import Foundation

struct Quarterback: Identifiable, Hashable {
    // Use playerId as stable id when available.
    let id: String
    let name: String
    let playerId: String?
    let team: String?

    // Passing stats
    let completions: Int?
    let attempts: Int?
    let passingYards: Int?
    let touchdowns: Int?
    let interceptions: Int?
    let passerRating: Double?

    // Additional stats present in the CSV
    let rushingYards: Int?
    let rushingTouchdowns: Int?
    let receivingReceptions: Int?
    let receivingYards: Int?
    let receivingTouchdowns: Int?

    // Summary
    let rank: Int?
    let totalPoints: Double?
}
