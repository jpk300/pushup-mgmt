import SwiftUI
import Combine
import UserNotifications
import ARKit
import AVFoundation
import UIKit

@main
struct PushManagerApp: App {
    @StateObject private var store = PushupStore()

    var body: some Scene {
        WindowGroup {
            PushManagerView()
                .environmentObject(store)
                .tint(.blueSteel)
                .onAppear {
                    store.load()
                }
        }
    }
}

@MainActor
final class PushupStore: ObservableObject {
    @Published var targetType: TargetType = .dailyTotal
    @Published var dailyTarget: Int = 50
    @Published var incrementSize: Int = 10
    @Published var setsPerDay: Int = 5
    @Published var entries: [PushupEntry] = [] {
        didSet {
            recalculateDailyTotals()
        }
    }
    @Published var reminderEnabled: Bool = false
    @Published var reminderTimes: [ReminderTime] = [ReminderTime(time: PushupStore.defaultReminderTime())]
    @Published var quietHoursEnabled: Bool = false
    @Published var quietHoursStart: Date = PushupStore.defaultQuietHoursStart()
    @Published var quietHoursEnd: Date = PushupStore.defaultQuietHoursEnd()
    @Published var showMonthly: Bool = true
    @Published var showQuarterly: Bool = true
    @Published var showYearly: Bool = true

    private let storageKey = "pushManagerStore"
    private var dailyTotalsCache: [Date: Int] = [:]

    static func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    }

    static func defaultQuietHoursStart() -> Date {
        Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    }

    static func defaultQuietHoursEnd() -> Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    }

    func dailyTargetTotal() -> Int {
        targetType == .incremental ? incrementSize * setsPerDay : dailyTarget
    }

    func addEntry(count: Int) {
        entries.append(PushupEntry(count: count, timestamp: Date()))
        save()
        NotificationScheduler.updateReminder(store: self) { _ in }
    }

    func updateEntry(id: UUID, count: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index] = PushupEntry(id: id, count: count, timestamp: entries[index].timestamp)
        save()
        NotificationScheduler.updateReminder(store: self) { _ in }
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
        NotificationScheduler.updateReminder(store: self) { _ in }
    }

    func total(for day: Date) -> Int {
        let dayStart = Calendar.current.startOfDay(for: day)
        return dailyTotals[dayStart] ?? 0
    }

    func streak() -> Int {
        let target = dailyTargetTotal()
        guard target > 0 else { return 0 }

        var current = Date()
        var days = 0
        while total(for: current) >= target {
            days += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: current) else {
                break
            }
            current = previous
        }
        return days
    }

    func totals(for range: RangeOption) -> [RangeEntry] {
        range.dates().map { date in
            RangeEntry(date: date, total: total(for: date))
        }
    }

    func chartEntries(for range: RangeOption) -> [ChartEntry] {
        switch range {
        case .daily, .weekly, .monthly:
            return totals(for: range).map { entry in
                ChartEntry(date: entry.date, value: Double(entry.total))
            }
        case .quarterly:
            return averagedEntries(range: range, bucketSize: 7)
        case .yearly:
            return averagedEntries(range: range, bucketSize: 14)
        }
    }

    private func averagedEntries(range: RangeOption, bucketSize: Int) -> [ChartEntry] {
        let dates = range.dates()
        guard !dates.isEmpty else { return [] }
        var results: [ChartEntry] = []
        var index = 0
        while index < dates.count {
            let end = min(index + bucketSize, dates.count)
            let bucket = dates[index..<end]
            let sum = bucket.reduce(0) { partial, date in
                partial + total(for: date)
            }
            let average = Double(sum) / Double(bucket.count)
            if let bucketDate = bucket.last {
                results.append(ChartEntry(date: bucketDate, value: average))
            }
            index = end
        }
        return results
    }

    func save() {
        let payload = StorePayload(
            targetType: targetType,
            dailyTarget: dailyTarget,
            incrementSize: incrementSize,
            setsPerDay: setsPerDay,
            entries: entries,
            reminderEnabled: reminderEnabled,
            reminderTimes: reminderTimes,
            quietHoursEnabled: quietHoursEnabled,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd,
            showMonthly: showMonthly,
            showQuarterly: showQuarterly,
            showYearly: showYearly
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode(StorePayload.self, from: data) else {
            return
        }
        targetType = payload.targetType
        dailyTarget = payload.dailyTarget
        incrementSize = payload.incrementSize
        setsPerDay = payload.setsPerDay
        entries = payload.entries
        reminderEnabled = payload.reminderEnabled
        reminderTimes = payload.reminderTimes
        quietHoursEnabled = payload.quietHoursEnabled
        quietHoursStart = payload.quietHoursStart
        quietHoursEnd = payload.quietHoursEnd
        showMonthly = payload.showMonthly
        showQuarterly = payload.showQuarterly
        showYearly = payload.showYearly
        recalculateDailyTotals()
    }

    func addReminderTime(_ time: Date) {
        reminderTimes.append(ReminderTime(time: time))
        reminderTimes.sort { $0.time < $1.time }
        save()
    }

    func removeReminderTime(at index: Int) {
        guard reminderTimes.indices.contains(index) else { return }
        reminderTimes.remove(at: index)
        save()
    }

    private func recalculateDailyTotals() {
        dailyTotalsCache = Dictionary(grouping: entries, by: { Calendar.current.startOfDay(for: $0.timestamp) })
            .mapValues { $0.reduce(0) { $0 + $1.count } }
    }

    private var dailyTotals: [Date: Int] {
        dailyTotalsCache
    }
}

struct StorePayload: Codable {
    var targetType: TargetType
    var dailyTarget: Int
    var incrementSize: Int
    var setsPerDay: Int
    var entries: [PushupEntry]
    var reminderEnabled: Bool
    var reminderTimes: [ReminderTime]
    var quietHoursEnabled: Bool
    var quietHoursStart: Date
    var quietHoursEnd: Date
    var showMonthly: Bool
    var showQuarterly: Bool
    var showYearly: Bool

    init(
        targetType: TargetType,
        dailyTarget: Int,
        incrementSize: Int,
        setsPerDay: Int,
        entries: [PushupEntry],
        reminderEnabled: Bool,
        reminderTimes: [ReminderTime],
        quietHoursEnabled: Bool,
        quietHoursStart: Date,
        quietHoursEnd: Date,
        showMonthly: Bool,
        showQuarterly: Bool,
        showYearly: Bool
    ) {
        self.targetType = targetType
        self.dailyTarget = dailyTarget
        self.incrementSize = incrementSize
        self.setsPerDay = setsPerDay
        self.entries = entries
        self.reminderEnabled = reminderEnabled
        self.reminderTimes = reminderTimes
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.showMonthly = showMonthly
        self.showQuarterly = showQuarterly
        self.showYearly = showYearly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetType = try container.decode(TargetType.self, forKey: .targetType)
        dailyTarget = try container.decode(Int.self, forKey: .dailyTarget)
        incrementSize = try container.decode(Int.self, forKey: .incrementSize)
        setsPerDay = try container.decode(Int.self, forKey: .setsPerDay)
        entries = try container.decode([PushupEntry].self, forKey: .entries)
        reminderEnabled = try container.decode(Bool.self, forKey: .reminderEnabled)
        showMonthly = (try? container.decode(Bool.self, forKey: .showMonthly)) ?? true
        showQuarterly = (try? container.decode(Bool.self, forKey: .showQuarterly)) ?? true
        showYearly = (try? container.decode(Bool.self, forKey: .showYearly)) ?? true
        quietHoursEnabled = (try? container.decode(Bool.self, forKey: .quietHoursEnabled)) ?? false
        quietHoursStart = (try? container.decode(Date.self, forKey: .quietHoursStart)) ?? PushupStore.defaultQuietHoursStart()
        quietHoursEnd = (try? container.decode(Date.self, forKey: .quietHoursEnd)) ?? PushupStore.defaultQuietHoursEnd()
        if let times = try? container.decode([ReminderTime].self, forKey: .reminderTimes) {
            reminderTimes = times
        } else if let legacyTime = try? container.decode(Date.self, forKey: .reminderTime) {
            reminderTimes = [ReminderTime(time: legacyTime)]
        } else {
            reminderTimes = [ReminderTime(time: PushupStore.defaultReminderTime())]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetType, forKey: .targetType)
        try container.encode(dailyTarget, forKey: .dailyTarget)
        try container.encode(incrementSize, forKey: .incrementSize)
        try container.encode(setsPerDay, forKey: .setsPerDay)
        try container.encode(entries, forKey: .entries)
        try container.encode(reminderEnabled, forKey: .reminderEnabled)
        try container.encode(reminderTimes, forKey: .reminderTimes)
        try container.encode(quietHoursEnabled, forKey: .quietHoursEnabled)
        try container.encode(quietHoursStart, forKey: .quietHoursStart)
        try container.encode(quietHoursEnd, forKey: .quietHoursEnd)
        try container.encode(showMonthly, forKey: .showMonthly)
        try container.encode(showQuarterly, forKey: .showQuarterly)
        try container.encode(showYearly, forKey: .showYearly)
    }

    enum CodingKeys: String, CodingKey {
        case targetType
        case dailyTarget
        case incrementSize
        case setsPerDay
        case entries
        case reminderEnabled
        case reminderTimes
        case reminderTime
        case quietHoursEnabled
        case quietHoursStart
        case quietHoursEnd
        case showMonthly
        case showQuarterly
        case showYearly
    }
}

struct PushupEntry: Identifiable, Codable {
    let id: UUID
    let count: Int
    let timestamp: Date

    init(id: UUID = UUID(), count: Int, timestamp: Date) {
        self.id = id
        self.count = count
        self.timestamp = timestamp
    }
}

struct RangeEntry: Identifiable {
    let id = UUID()
    let date: Date
    let total: Int
}

struct ReminderTime: Identifiable, Codable, Hashable {
    let id: UUID
    var time: Date

    init(id: UUID = UUID(), time: Date) {
        self.id = id
        self.time = time
    }
}

struct ChartEntry: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum TargetType: String, CaseIterable, Codable, Identifiable {
    case dailyTotal
    case incremental

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyTotal:
            return "Daily total"
        case .incremental:
            return "Incremental sets"
        }
    }
}

enum RangeOption: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    func dates() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayCount: Int
        switch self {
        case .daily:
            dayCount = 1
        case .weekly:
            dayCount = 7
        case .monthly:
            dayCount = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        case .quarterly:
            let month = calendar.component(.month, from: today)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var totalDays = 0
            for offset in 0..<3 {
                var components = calendar.dateComponents([.year], from: today)
                components.month = quarterStartMonth + offset
                if let monthDate = calendar.date(from: components) {
                    totalDays += calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
                }
            }
            dayCount = totalDays
        case .yearly:
            dayCount = calendar.range(of: .day, in: .year, for: today)?.count ?? 365
        }
        return (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: -(dayCount - 1 - offset), to: today)
        }
    }
}

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
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink("Push-up Camera") {
                        CameraView()
                    }
                    .foregroundColor(.blue)
                }
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
                HStack {
                    TextField("Push-ups completed", text: $logCount)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isLogFieldFocused)
                        .onChange(of: logCount) { _ in
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
                            .onChange(of: editCount) { _ in
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
                .onChange(of: store.showMonthly) { _ in ensureValidRangeSelection() }
                .onChange(of: store.showQuarterly) { _ in ensureValidRangeSelection() }
                .onChange(of: store.showYearly) { _ in ensureValidRangeSelection() }

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

struct AdminView: View {
    @EnvironmentObject private var store: PushupStore
    @State private var showingNotificationAlert = false
    @State private var newReminderTime: Date = PushupStore.defaultReminderTime()
    @State private var showingReminderResult = false
    @State private var reminderResultMessage = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                targetSection
                insightsSettingsSection
                remindersSection
            }
            .padding()
        }
        .navigationTitle("Settings")
        .alert("Notifications Disabled", isPresented: $showingNotificationAlert) {
            Button("OK") { }
        } message: {
            Text("Enable notifications in Settings to receive reminders.")
        }
        .alert("Reminder status", isPresented: $showingReminderResult) {
            Button("OK") { }
        } message: {
            Text(reminderResultMessage)
        }
    }

    private var targetSection: some View {
        SectionCard(title: "Set your daily target") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Target type", selection: $store.targetType) {
                    ForEach(TargetType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if store.targetType == .dailyTotal {
                    Stepper(value: $store.dailyTarget, in: 1...1000) {
                        Text("Daily push-up target: \(store.dailyTarget)")
                    }
                } else {
                    Stepper(value: $store.incrementSize, in: 1...200) {
                        Text("Push-ups per set: \(store.incrementSize)")
                    }
                    Stepper(value: $store.setsPerDay, in: 1...50) {
                        Text("Sets per day: \(store.setsPerDay)")
                    }
                }
            }
            .onChange(of: store.targetType) { _ in store.save() }
            .onChange(of: store.dailyTarget) { _ in store.save() }
            .onChange(of: store.incrementSize) { _ in store.save() }
            .onChange(of: store.setsPerDay) { _ in store.save() }
        }
    }

    private var remindersSection: some View {
        SectionCard(title: "Notification setup") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push-up reminders")
                            .font(.headline)
                        Text("Get nudges if you are behind on your daily target.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Enable daily reminders", isOn: $store.reminderEnabled)
                Text("When enabled, we will send a notification at each time you set below.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if store.reminderEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reminder times")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(store.reminderTimes.indices, id: \.self) { index in
                            HStack {
                                DatePicker(
                                    "Reminder",
                                    selection: $store.reminderTimes[index].time,
                                    displayedComponents: .hourAndMinute
                                )
                                Button("Remove") {
                                    store.removeReminderTime(at: index)
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        HStack {
                            DatePicker("New reminder time", selection: $newReminderTime, displayedComponents: .hourAndMinute)
                            Button("Add time") {
                                store.addReminderTime(newReminderTime)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable quiet hours", isOn: $store.quietHoursEnabled)
                        if store.quietHoursEnabled {
                            HStack {
                                DatePicker("Quiet hours start", selection: $store.quietHoursStart, displayedComponents: .hourAndMinute)
                                DatePicker("Quiet hours end", selection: $store.quietHoursEnd, displayedComponents: .hourAndMinute)
                            }
                        }
                    }

                    Button("Save reminders") {
                        NotificationScheduler.updateReminder(store: store) { authorized in
                            if !authorized {
                                store.reminderEnabled = false
                                showingNotificationAlert = true
                                reminderResultMessage = "Reminders not saved. Enable notifications in Settings."
                                showingReminderResult = true
                            }
                            if authorized {
                                reminderResultMessage = "Reminders saved."
                                showingReminderResult = true
                            }
                            store.save()
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Turn on reminders above, then add times to schedule your notifications.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(reminderStatusText())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onChange(of: store.reminderEnabled) { _ in
                NotificationScheduler.updateReminder(store: store) { authorized in
                    if !authorized {
                        store.reminderEnabled = false
                        showingNotificationAlert = true
                        reminderResultMessage = "Notifications are disabled. Enable them in Settings."
                        showingReminderResult = true
                    } else {
                        reminderResultMessage = store.reminderEnabled ? "Reminders enabled." : "Reminders turned off."
                        showingReminderResult = true
                    }
                    store.save()
                }
            }
            .onChange(of: store.quietHoursEnabled) { _ in
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.quietHoursStart) { _ in
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.quietHoursEnd) { _ in
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
        }
    }

    private var insightsSettingsSection: some View {
        SectionCard(title: "Insights time frames") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily and weekly are always shown. Toggle additional ranges below.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Show monthly", isOn: $store.showMonthly)
                Toggle("Show quarterly", isOn: $store.showQuarterly)
                Toggle("Show yearly", isOn: $store.showYearly)
            }
            .onChange(of: store.showMonthly) { _ in store.save() }
            .onChange(of: store.showQuarterly) { _ in store.save() }
            .onChange(of: store.showYearly) { _ in store.save() }
        }
    }

    private func reminderStatusText() -> String {
        guard store.reminderEnabled else {
            return "Reminders are off."
        }
        if store.reminderTimes.isEmpty {
            return "Add at least one reminder time."
        }
        let times = store.reminderTimes
            .map { $0.time.formatted(DateFormats.reminderTime) }
            .joined(separator: ", ")
        if store.quietHoursEnabled {
            let quietStart = store.quietHoursStart.formatted(DateFormats.reminderTime)
            let quietEnd = store.quietHoursEnd.formatted(DateFormats.reminderTime)
            return "Reminders set for \(times). Quiet hours: \(quietStart)–\(quietEnd)."
        }
        return "Reminders set for \(times)."
    }

}

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PushupStore
    @State private var cameraCount: Int = 0
    @State private var cameraStatus: String = "Not calibrated"
    @State private var cameraDistance: Double?
    @State private var showingCameraAlert = false
    @State private var cameraAlertMessage = ""
    @State private var isCounting: Bool = false
    @State private var isCalibrated: Bool = false
    @State private var showCalibrationOverlay: Bool = true
    @State private var pendingSaveCount: Int?
    @State private var showingSaveConfirmation: Bool = false
    @State private var showFlash: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SectionCard(title: "Camera push-up counter") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Use the iPhone TrueDepth camera to estimate face distance for push-up counting.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ZStack {
                            CameraPushupCounterView(
                                count: $cameraCount,
                                statusText: $cameraStatus,
                                currentDistance: $cameraDistance,
                                isCounting: $isCounting,
                                isCalibrated: $isCalibrated,
                                showFlash: $showFlash,
                                onPermissionResult: { message in
                                    cameraAlertMessage = message
                                    showingCameraAlert = true
                                }
                            )
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            if showFlash {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.4))
                                    .transition(.opacity)
                                    .allowsHitTesting(false)
                            }

                            if showCalibrationOverlay {
                                CalibrationOverlayView(
                                    isCalibrated: isCalibrated,
                                    hasFaceLock: cameraDistance != nil,
                                    isCounting: isCounting,
                                    statusText: cameraStatus,
                                    onDismiss: { showCalibrationOverlay = false },
                                    onReset: resetCalibration
                                )
                                .transition(.opacity)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Push-ups counted")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(cameraCount)")
                                .font(.system(size: 56, weight: .bold))
                        }

                        if let distance = cameraDistance {
                            Text("Estimated distance: \(distance.formatted(.number.precision(.fractionLength(2)))) m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(cameraStatus)
                            .font(.headline)
                            .foregroundColor(.primary)

                        HStack {
                            Button("Start counting") {
                                isCounting = true
                                cameraStatus = "Counting started."
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Stop counting") {
                                stopCounting()
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Reset calibration") {
                            resetCalibration()
                        }
                        .buttonStyle(.bordered)

                        if !showCalibrationOverlay {
                            Button("Show calibration tips") {
                                showCalibrationOverlay = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Push-up Camera")
        .alert("Camera access", isPresented: $showingCameraAlert) {
            Button("OK") { }
        } message: {
            Text(cameraAlertMessage)
        }
        .alert("Save push-ups?", isPresented: $showingSaveConfirmation) {
            Button("Save") {
                finalizeStop(shouldSave: true)
            }
            Button("Discard", role: .destructive) {
                finalizeStop(shouldSave: false)
            }
        } message: {
            Text("Save \(pendingSaveCount ?? 0) push-ups to your log?")
        }
        .onChange(of: isCalibrated) { newValue in
            if newValue {
                showCalibrationOverlay = false
            }
        }
    }

    private func stopCounting() {
        isCounting = false
        cameraStatus = "Counting stopped. Review your session."
        guard cameraCount > 0 else {
            resetCameraSession(shouldDismiss: true)
            return
        }
        pendingSaveCount = cameraCount
        showingSaveConfirmation = true
    }

    private func finalizeStop(shouldSave: Bool) {
        if shouldSave, let count = pendingSaveCount, count > 0 {
            store.addEntry(count: count)
        }
        resetCameraSession(shouldDismiss: true)
        pendingSaveCount = nil
    }

    private func resetCalibration() {
        cameraCount = 0
        cameraStatus = "Not calibrated"
        cameraDistance = nil
        isCalibrated = false
        NotificationCenter.default.post(name: .resetPushupCalibration, object: nil)
    }

    private func resetCameraSession(shouldDismiss: Bool) {
        resetCalibration()
        if shouldDismiss {
            dismiss()
        }
    }
}

extension Notification.Name {
    static let resetPushupCalibration = Notification.Name("resetPushupCalibration")
}

struct CameraPushupCounterView: UIViewRepresentable {
    @Binding var count: Int
    @Binding var statusText: String
    @Binding var currentDistance: Double?
    @Binding var isCounting: Bool
    @Binding var isCalibrated: Bool
    @Binding var showFlash: Bool
    let onPermissionResult: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            count: $count,
            statusText: $statusText,
            currentDistance: $currentDistance,
            isCounting: $isCounting,
            isCalibrated: $isCalibrated,
            showFlash: $showFlash,
            onPermissionResult: onPermissionResult
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.scene = SCNScene()
        context.coordinator.attachBlurOverlay(to: view)
        context.coordinator.startSession(on: view.session)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    final class Coordinator: NSObject, ARSessionDelegate {
        @Binding private var count: Int
        @Binding private var statusText: String
        @Binding private var currentDistance: Double?
        @Binding private var isCounting: Bool
        @Binding private var isCalibrated: Bool
        @Binding private var showFlash: Bool
        private let onPermissionResult: (String) -> Void
        private var baselineDistance: Double?
        private var isNear: Bool = false
        private weak var session: ARSession?
        private weak var sceneView: ARSCNView?
        private weak var blurView: UIVisualEffectView?
        private let maskLayer = CAShapeLayer()

        init(
            count: Binding<Int>,
            statusText: Binding<String>,
            currentDistance: Binding<Double?>,
            isCounting: Binding<Bool>,
            isCalibrated: Binding<Bool>,
            showFlash: Binding<Bool>,
            onPermissionResult: @escaping (String) -> Void
        ) {
            _count = count
            _statusText = statusText
            _currentDistance = currentDistance
            _isCounting = isCounting
            _isCalibrated = isCalibrated
            _showFlash = showFlash
            self.onPermissionResult = onPermissionResult
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(resetCalibration), name: .resetPushupCalibration, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self, name: .resetPushupCalibration, object: nil)
            session?.pause()
        }

        func attachBlurOverlay(to view: ARSCNView) {
            sceneView = view
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            blur.frame = view.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            maskLayer.fillRule = .evenOdd
            blur.layer.mask = maskLayer
            view.addSubview(blur)
            blurView = blur
            updateBlurMask(center: CGPoint(x: view.bounds.midX, y: view.bounds.midY), in: view.bounds)
        }

        func startSession(on session: ARSession) {
            self.session = session
            guard ARFaceTrackingConfiguration.isSupported else {
                statusText = "Face tracking requires a TrueDepth camera."
                return
            }
            requestCameraAccessIfNeeded()
        }

        private func requestCameraAccessIfNeeded() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                runSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.onPermissionResult("Camera access granted.")
                            self.runSession()
                        } else {
                            self.statusText = "Camera access denied."
                            self.onPermissionResult("Camera access denied. Enable it in Settings.")
                        }
                    }
                }
            case .denied, .restricted:
                statusText = "Camera access denied."
                onPermissionResult("Camera access denied. Enable it in Settings.")
            @unknown default:
                statusText = "Camera access unavailable."
                onPermissionResult("Camera access unavailable.")
            }
        }

        private func runSession() {
            guard let session else { return }
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            statusText = "Look at the camera to calibrate."
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            let faceTransform = faceAnchor.transform
            let zDistance = abs(Double(faceTransform.columns.3.z))
            DispatchQueue.main.async {
                self.currentDistance = zDistance
                self.handleDistance(zDistance)
                if let point = self.projectFaceCenter(faceTransform) {
                    self.updateBlurMask(center: point, in: self.sceneView?.bounds ?? .zero)
                }
            }
        }

        private func projectFaceCenter(_ transform: simd_float4x4) -> CGPoint? {
            guard let sceneView else { return nil }
            let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let projected = sceneView.projectPoint(SCNVector3(position))
            return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        }

        private func updateBlurMask(center: CGPoint, in bounds: CGRect) {
            guard bounds.width > 0, bounds.height > 0 else { return }
            let radius: CGFloat = 120
            let path = UIBezierPath(rect: bounds)
            let holeRect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            path.append(UIBezierPath(ovalIn: holeRect))
            maskLayer.frame = bounds
            maskLayer.path = path.cgPath
        }

        private func handleDistance(_ distance: Double) {
            let nearThresholdMeters = 0.15
            let toleranceMeters = 0.05

            if baselineDistance == nil {
                baselineDistance = distance
                isCalibrated = true
                statusText = "Calibrated at \(distance.formatted(.number.precision(.fractionLength(2)))) m. Begin push-ups."
                return
            }

            guard isCounting else {
                statusText = "Counting paused."
                return
            }

            guard let baselineDistance = baselineDistance else { return }
            let nearDistance = max(baselineDistance - nearThresholdMeters, 0.05)
            if distance <= nearDistance && !isNear {
                isNear = true
                statusText = "Down position detected."
            } else if distance >= baselineDistance - toleranceMeters && isNear {
                isNear = false
                count += 1
                statusText = "Up position detected. Push-up counted."
                showFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.showFlash = false
                }
            }
        }

        @objc private func resetCalibration() {
            baselineDistance = nil
            isNear = false
            isCalibrated = false
            statusText = "Not calibrated"
        }
    }
}

struct CalibrationOverlayView: View {
    let isCalibrated: Bool
    let hasFaceLock: Bool
    let isCounting: Bool
    let statusText: String
    let onDismiss: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Camera calibration")
                    .font(.headline)
                Spacer()
                Button("Dismiss") {
                    onDismiss()
                }
                .font(.caption)
            }

            Text("Follow these steps before starting your set.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                overlayStep(
                    title: "Keep your face centered in the frame.",
                    isComplete: hasFaceLock
                )
                overlayStep(
                    title: "Hold still to calibrate your starting distance.",
                    isComplete: isCalibrated
                )
                overlayStep(
                    title: "Tap Start counting when ready.",
                    isComplete: isCounting
                )
            }

            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Reset calibration") {
                    onReset()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Got it") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(12)
    }

    private func overlayStep(title: String, isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isComplete ? .green : .secondary)
            Text(title)
                .font(.caption)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blueSteel.opacity(0.15))
        .cornerRadius(16)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blueSteel.opacity(0.08))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

struct BarChart: View {
    let entries: [RangeEntry]

    var body: some View {
        let maxValue = max(entries.map { $0.total }.max() ?? 1, 1)
        VStack(spacing: 10) {
            ForEach(entries.suffix(10)) { entry in
                HStack {
                    Text(entry.date, format: DateFormats.chartDay)
                        .font(.caption)
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.blue.opacity(0.2))
                            Capsule().fill(Color.blue)
                                .frame(width: geometry.size.width * CGFloat(entry.total) / CGFloat(maxValue))
                        }
                    }
                    .frame(height: 8)
                    Text("\(entry.total)")
                        .font(.caption)
                        .frame(width: 32, alignment: .trailing)
                }
                .frame(height: 18)
            }
        }
    }
}

struct LineChart: View {
    let entries: [ChartEntry]

    var body: some View {
        let values = entries.map { $0.value }
        let maxValue = max(values.max() ?? 1, 1)
        let minValue = min(values.min() ?? 0, maxValue)
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let step = entries.count > 1 ? width / CGFloat(entries.count - 1) : 0
            let range = max(maxValue - minValue, 1)
            let points = entries.enumerated().map { index, entry in
                let x = CGFloat(index) * step
                let normalized = (entry.value - minValue) / range
                let y = height - CGFloat(normalized) * height
                return CGPoint(x: x, y: y)
            }

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.blue, lineWidth: 2)

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
        }
        .frame(height: 180)
    }
}

enum DateFormats {
    static let reminderTime = Date.FormatStyle(date: .omitted, time: .shortened)
    static let chartDay = Date.FormatStyle.dateTime.month().day()
}

enum NotificationScheduler {
    static func updateReminder(store: PushupStore, completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            center.getPendingNotificationRequests { requests in
                let identifiers = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix("pushup-reminder-") }
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
                guard store.reminderEnabled, !store.reminderTimes.isEmpty else {
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                guard store.total(for: Date()) < store.dailyTargetTotal() else {
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                let reminders = filteredReminders(store: store)
                guard !reminders.isEmpty else {
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                for (index, reminder) in reminders.enumerated() {
                    let content = UNMutableNotificationContent()
                    content.title = "Push-up Manager reminder"
                    content.body = "Log your push-ups to stay on target today."

                    let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: reminder.time)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "pushup-reminder-\(index)",
                        content: content,
                        trigger: trigger
                    )
                    center.add(request)
                }
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    private static func filteredReminders(store: PushupStore) -> [ReminderTime] {
        guard store.quietHoursEnabled else { return store.reminderTimes }
        return store.reminderTimes.filter { reminder in
            !isInQuietHours(time: reminder.time, start: store.quietHoursStart, end: store.quietHoursEnd)
        }
    }

    private static func isInQuietHours(time: Date, start: Date, end: Date) -> Bool {
        let calendar = Calendar.current
        let timeMinutes = minutesSinceMidnight(for: time, calendar: calendar)
        let startMinutes = minutesSinceMidnight(for: start, calendar: calendar)
        let endMinutes = minutesSinceMidnight(for: end, calendar: calendar)
        if startMinutes == endMinutes {
            return true
        }
        if startMinutes < endMinutes {
            return timeMinutes >= startMinutes && timeMinutes < endMinutes
        }
        return timeMinutes >= startMinutes || timeMinutes < endMinutes
    }

    private static func minutesSinceMidnight(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

extension Color {
    static let blueSteel = Color(red: 0.27, green: 0.46, blue: 0.60)
}
