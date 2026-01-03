import SwiftUI

struct QBDetailView: View {
    let qb: Quarterback
    @EnvironmentObject private var viewModel: QBViewModel
    @State private var selectedTeamId: String = ""
    @State private var selectedWeek: Int = 0 // 0 == All

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(qb.name)
                            .font(.title)
                            .bold()

                        if let team = qb.team {
                            Text(team)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let rank = qb.rank {
                        Text("#\(rank)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                // Compact stat grid
                let stats: [(String, String)] = [
                    ("Pass Yards", qb.passingYards.map(String.init) ?? "—"),
                    ("Pass TDs", qb.touchdowns.map(String.init) ?? "—"),
                    ("INTs", qb.interceptions.map(String.init) ?? "—"),
                    ("Passer Rating", qb.passerRating.map { String(format: "%.1f", $0) } ?? "—"),
                    ("Rush Y", qb.rushingYards.map(String.init) ?? "—"),
                    ("Rush TDs", qb.rushingTouchdowns.map(String.init) ?? "—"),
                    ("Receptions", qb.receivingReceptions.map(String.init) ?? "—"),
                    ("Rec Y", qb.receivingYards.map(String.init) ?? "—")
                ]

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(stats, id: \.0) { stat in
                        StatCard(title: stat.0, value: stat.1)
                    }
                }

                // Total points card
                StatCard(title: "Total Points", value: qb.totalPoints.map { String(format: "%.2f", $0) } ?? "—")

                Divider()

                Group {
                    Text("Matchup")
                        .font(.headline)

                    if viewModel.teamStats.isEmpty {
                        VStack(spacing: 8) {
                            Text("Loading team defensive data…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ProgressView()
                        }
                        .task {
                            await viewModel.loadTeamStats()
                        }
                    } else {
                        Picker("Opponent", selection: $selectedTeamId) {
                            Text("Select opponent").tag("")
                            ForEach(viewModel.teamStats, id: \.id) { team in
                                Text(team.team).tag(team.id)
                            }
                        }
                        .pickerStyle(.menu)

                        // week picker based on available weeks for selected opponent
                        if let opponent = viewModel.teamStats.first(where: { $0.id == selectedTeamId }) {
                            let weeks = viewModel.weeks(for: opponent.team)

                            Picker("Through week", selection: $selectedWeek) {
                                Text("All").tag(0)
                                ForEach(weeks, id: \.self) { w in
                                    Text("Week \(w)").tag(w)
                                }
                            }
                            .pickerStyle(.segmented)

                            let weekParam: Int? = selectedWeek == 0 ? nil : selectedWeek
                            let prediction = viewModel.predictMatchup(for: qb, againstTeamName: opponent.team, throughWeek: weekParam)

                            // compute opponent weeks count and compare predicted per-game values vs QB per-week averages
                            let weeksCount = max(1, viewModel.teamStats.filter { ts in
                                ts.team == opponent.team && (weekParam == nil || (ts.week ?? Int.max) <= weekParam!)
                            }.count)

                            let currentPerWeek = qb.passingYards.map(Double.init).map { $0 / Double(weeksCount) }
                            let predicted = prediction.predictedPassingYards
                            let isUp = (predicted ?? 0) > (currentPerWeek ?? 0)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(prediction.summary)
                                    .font(.body)
                                if let py = predicted {
                                    Text("Predicted Passing Yards (game): \(Int(py))")
                                        .font(.title3).bold()
                                        .foregroundColor(isUp ? .green : .red)
                                }
                                if let ptd = prediction.predictedPassingTDs {
                                    Text("Predicted Passing TDs (game): \(String(format: "%.1f", ptd))")
                                        .font(.subheadline)
                                }
                            }
                            .padding()
                            .background(isUp ? Color.green.opacity(0.08) : Color.red.opacity(0.06))
                            .cornerRadius(10)
                        } else {
                            Text("Choose an opponent to see a quick prediction")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .onChange(of: viewModel.teamStats) { new in
                if selectedTeamId.isEmpty {
                    // Prefer a default opponent that is not the QB's own team
                    if let defaultTeam = new.first(where: { $0.team != qb.team }) {
                        selectedTeamId = defaultTeam.id
                    } else {
                        selectedTeamId = new.first?.id ?? ""
                    }
                }
            }
            .task {
                // ensure team stats available when this view appears
                await viewModel.loadTeamStats()
            }
        }
        .navigationTitle(qb.name)
    }
}

private struct StatRow: View {
    let title: String
    let text: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(text ?? "—")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .bold()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
    }
}

#Preview {
    QBDetailView(qb: Quarterback(
        id: "1",
        name: "Sample QB",
        playerId: "1",
        team: "XYZ",
        completions: 0,
        attempts: 0,
        passingYards: 3000,
        touchdowns: 20,
        interceptions: 5,
        passerRating: 95.5,
        rushingYards: 200,
        rushingTouchdowns: 2,
        receivingReceptions: nil,
        receivingYards: nil,
        receivingTouchdowns: nil,
        rank: 1,
        totalPoints: 304.65
    ))
}
