//
//  PushManagerView.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

struct PushManagerView: View {
    @EnvironmentObject private var store: PushupStore
    @State private var logCount: String = ""
    @State private var logErrorMessage: String?
    @State private var rangeOption: RangeOption = .weekly
    @State private var editingEntry: PushupEntry?
    @State private var editCount: String = ""
    @State private var editErrorMessage: String?
    @FocusState private var isLogFieldFocused: Bool
    private var availableRanges: [RangeOption] {
        var ranges: [RangeOption] = [.daily, .weekly]
        if store.showMonthly { ranges.append(.monthly) }
        if store.showQuarterly { ranges.append(.quarterly) }
        if store.showYearly { ranges.append(.yearly) }
        return ranges
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                    logSection
                    insightsSection
                }
                .padding()
            }
            .navigationTitle("Push-Up Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Settings") {
                        AdminView()
                            .environmentObject(store)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stay on track with daily push-ups.")
                .font(.title2)
                .fontWeight(.semibold)
            HStack(spacing: 16) {
                StatCard(title: "Today", value: "\(store.total(for: Date()))", subtitle: "Target: \(store.dailyTargetTotal())")
                StatCard(title: "Streak", value: "\(store.streak())", subtitle: "days hit target")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logSection: some View {
        SectionCard(title: "Log push-ups") {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink("Log with camera") {
                    CameraView()
                        .environmentObject(store)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    TextField("Push-ups completed", text: $logCount)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isLogFieldFocused)
                        .onChange(of: logCount) {
                            logErrorMessage = nil
                        }
                    Button("Add set") {
                        guard let count = Int(logCount), count > 0 else {
                            logErrorMessage = "Enter a number greater than zero."
                            return
                        }
                        store.addEntry(count: count)
                        logCount = ""
                        logErrorMessage = nil
                        isLogFieldFocused = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let logErrorMessage {
                    Text(logErrorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                ProgressView(value: Double(store.total(for: Date())), total: Double(max(store.dailyTargetTotal(), 1)))
                Text("\(store.total(for: Date())) / \(store.dailyTargetTotal())")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    let todaysEntries = store.entries.filter { Calendar.current.isDateInToday($0.timestamp) }
                    if todaysEntries.isEmpty {
                        Text("No sets logged yet today.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(todaysEntries.reversed()) { entry in
                            HStack {
                                Text("\(entry.count) push-ups")
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .foregroundColor(.secondary)
                                Button("Edit") {
                                    editingEntry = entry
                                    editCount = "\(entry.count)"
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .contextMenu {
                                Button("Edit") {
                                    editingEntry = entry
                                    editCount = "\(entry.count)"
                                }
                                Button("Delete", role: .destructive) {
                                    store.removeEntry(id: entry.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                Form {
                    Section(header: Text("Update set")) {
                        TextField("Push-ups", text: $editCount)
                            .keyboardType(.numberPad)
                            .onChange(of: editCount) {
                                editErrorMessage = nil
                            }
                        if let editErrorMessage {
                            Text(editErrorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    Section {
                        Button("Save changes") {
                            guard let count = Int(editCount), count > 0 else {
                                editErrorMessage = "Enter a number greater than zero."
                                return
                            }
                            store.updateEntry(id: entry.id, count: count)
                            editErrorMessage = nil
                            editingEntry = nil
                        }
                        Button("Delete set", role: .destructive) {
                            store.removeEntry(id: entry.id)
                            editErrorMessage = nil
                            editingEntry = nil
                        }
                    }
                }
                .navigationTitle("Edit set")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editingEntry = nil
                        }
                    }
                }
            }
            .onAppear {
                editErrorMessage = nil
            }
        }
    }

    private var insightsSection: some View {
        SectionCard(title: "Insights") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $rangeOption) {
                    ForEach(availableRanges) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.showMonthly) { ensureValidRangeSelection() }
                .onChange(of: store.showQuarterly) { ensureValidRangeSelection() }
                .onChange(of: store.showYearly) { ensureValidRangeSelection() }

                let totals = store.totals(for: rangeOption)
                let sum = totals.reduce(0) { $0 + $1.total }
                let average = totals.isEmpty ? 0 : Int(round(Double(sum) / Double(totals.count)))

                HStack {
                    VStack(alignment: .leading) {
                        Text("Total in range")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(sum)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Average per day")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(average)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }

                let chartEntries = store.chartEntries(for: rangeOption)
                if rangeOption == .monthly || rangeOption == .quarterly || rangeOption == .yearly {
                    LineChart(entries: chartEntries)
                } else {
                    BarChart(entries: totals)
                }
            }
        }
    }

    private func ensureValidRangeSelection() {
        if !availableRanges.contains(rangeOption) {
            rangeOption = .weekly
        }
    }
}
