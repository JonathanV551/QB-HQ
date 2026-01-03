import Foundation

struct TeamStats: Identifiable, Hashable {
    let id: String
    let team: String
    let week: Int?
    let stats: [String: Double]
}
