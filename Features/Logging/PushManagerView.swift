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
    @State private var showGoalCelebration: Bool = false
    @State private var lastTrackedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var lastTrackedTotal: Int = 0
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
                    activitySwitcher
                    heroSection
                    logSection
                    insightsSection
                }
                .padding()
            }
            .navigationTitle("\(store.selectedActivity.title) Tracker")
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
        .onAppear {
            lastTrackedDay = Calendar.current.startOfDay(for: Date())
            lastTrackedTotal = store.total(for: Date())
        }
        .onChange(of: store.selectedActivity) {
            lastTrackedDay = Calendar.current.startOfDay(for: Date())
            lastTrackedTotal = store.total(for: Date())
            logCount = ""
            logErrorMessage = nil
        }
        .onChange(of: store.entries) {
            evaluateGoalCelebration()
        }
        .alert("Goal achieved 🎉", isPresented: $showGoalCelebration) {
            Button("Awesome!") {}
        } message: {
            Text("You hit your \(store.selectedActivity.noun) target for today. Great work!")
        }
    }

    private var activitySwitcher: some View {
        SectionCard(title: "Activity") {
            Picker("Activity", selection: $store.selectedActivity) {
                ForEach(ActivityType.allCases) { activity in
                    Text(activity.title).tag(activity)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stay on track with daily \(store.selectedActivity.noun).")
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
        SectionCard(title: "Log \(store.selectedActivity.noun)") {
            VStack(alignment: .leading, spacing: 16) {
                let isRestDayToday = store.isRestDay(Date())
                HStack {
                    if store.selectedActivity == .pushups {
                        NavigationLink("Log with camera") {
                            CameraView()
                                .environmentObject(store)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button(isRestDayToday ? "Cancel rest day" : "Rest day") {
                        store.setRestDay(Date(), isRestDay: !isRestDayToday)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    TextField("\(store.selectedActivity.title) completed", text: $logCount)
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
                .disabled(isRestDayToday)
                if let logErrorMessage {
                    Text(logErrorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if isRestDayToday {
                      Text("Rest day selected. \(store.selectedActivity.title) are optional.")
                          .font(.caption)
                          .foregroundColor(.secondary)
                  }

                ProgressView(value: Double(store.total(for: Date())), total: Double(max(store.dailyTargetTotal(), 1)))
                Text("\(store.total(for: Date())) / \(store.dailyTargetTotal())")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    let todaysEntries = store.entries.filter {
                        $0.activityType == store.selectedActivity && Calendar.current.isDateInToday($0.timestamp)
                    }
                    if todaysEntries.isEmpty {
                        Text(isRestDayToday ? "Rest day logged." : "No sets logged yet today.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(todaysEntries.reversed()) { entry in
                            HStack {
                                Text("\(entry.count) \(store.selectedActivity.noun)")
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
                        TextField(store.selectedActivity.title, text: $editCount)
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

    private func evaluateGoalCelebration() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != lastTrackedDay {
            lastTrackedDay = today
            lastTrackedTotal = 0
        }
        let target = store.dailyTargetTotal()
        let currentTotal = store.total(for: Date())
        if target > 0, currentTotal >= target, lastTrackedTotal < target {
            showGoalCelebration = true
        }
        lastTrackedTotal = currentTotal
    }
}
