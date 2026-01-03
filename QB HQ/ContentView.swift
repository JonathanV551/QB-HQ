//
//  ContentView.swift
//  QB HQ
//
//  Created by Jonathan Vadala on 12/17/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = QBViewModel()
    @State private var searchText: String = ""
    @State private var showingHelp = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var filteredQuarterbacks: [Quarterback] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.quarterbacks
        } else {
            let lower = searchText.lowercased()
            return viewModel.quarterbacks.filter { qb in
                qb.name.lowercased().contains(lower) || (qb.team?.lowercased().contains(lower) ?? false)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.quarterbacks.isEmpty {
                    ProgressView("Loading quarterbacks…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredQuarterbacks) { qb in
                        NavigationLink(destination: QBDetailView(qb: qb)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(qb.team ?? "—")
                                            .font(.caption)
                                            .bold()
                                            .padding(6)
                                            .background(Color(.secondarySystemFill))
                                            .clipShape(Capsule())

                                        Text(qb.name)
                                            .font(.headline)
                                    }

                                    if let points = qb.totalPoints {
                                        Text("Fantasy: \(String(format: "%.2f", points))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing) {
                                    Text(qb.passingYards.map { String($0) } ?? "—")
                                        .monospacedDigit()
                                        .font(.headline)
                                    Text("YDS")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.loadQuarterbacks()
                        await viewModel.loadTeamStats()
                    }
                }
            }
            .navigationTitle("QB HQ")
            .searchable(text: $searchText, prompt: "Search QBs")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let last = viewModel.lastUpdated {
                        Text("Updated \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            Button("System") { appearanceMode = "system" }
                            Button("Light") { appearanceMode = "light" }
                            Button("Dark") { appearanceMode = "dark" }
                        } label: {
                            Image(systemName: appearanceMode == "dark" ? "moon.fill" : "moon.circle")
                        }

                        Button(action: { showingHelp = true }) { Image(systemName: "questionmark.circle") }
                        Button(action: {
                            Task {
                                await viewModel.loadQuarterbacks()
                                await viewModel.loadTeamStats()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                await viewModel.loadQuarterbacks()
                await viewModel.loadTeamStats()
            }
        }
        .environmentObject(viewModel)
        .preferredColorScheme(preferredScheme)
        .sheet(isPresented: $showingHelp) {
            VStack(spacing: 16) {
                Text("How predictions are made")
                    .font(.headline)
                Text("Predictions use team averages through the selected week and weigh pass yards, completion %, sacks and INTs to compute a factor applied to the QB's existing totals. It's a simple heuristic that is transparent and easy to refine.")
                    .padding()
                Button("Close") { showingHelp = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
