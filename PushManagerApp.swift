import SwiftUI
import UserNotifications

@main
struct PushManagerApp: App {
    @StateObject private var store = PushupStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    store.load()
                }
        }
    }
}

final class PushupStore: ObservableObject {
    @Published var targetType: TargetType = .dailyTotal
    @Published var dailyTarget: Int = 50
    @Published var incrementSize: Int = 10
    @Published var setsPerDay: Int = 5
    @Published var entries: [PushupEntry] = []
    @Published var reminderEnabled: Bool = false
    @Published var reminderTime: Date = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()

    private let storageKey = "pushManagerStore"

    func dailyTargetTotal() -> Int {
        targetType == .incremental ? incrementSize * setsPerDay : dailyTarget
    }

    func addEntry(count: Int) {
        entries.append(PushupEntry(count: count, timestamp: Date()))
        save()
    }

    func total(for day: Date) -> Int {
        entries
            .filter { Calendar.current.isDate($0.timestamp, inSameDayAs: day) }
            .reduce(0) { $0 + $1.count }
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

    func save() {
        let payload = StorePayload(
            targetType: targetType,
            dailyTarget: dailyTarget,
            incrementSize: incrementSize,
            setsPerDay: setsPerDay,
            entries: entries,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime
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
        reminderTime = payload.reminderTime
    }
}

struct StorePayload: Codable {
    var targetType: TargetType
    var dailyTarget: Int
    var incrementSize: Int
    var setsPerDay: Int
    var entries: [PushupEntry]
    var reminderEnabled: Bool
    var reminderTime: Date
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
        let today = Calendar.current.startOfDay(for: Date())
        let dayCount: Int
        switch self {
        case .daily:
            dayCount = 1
        case .weekly:
            dayCount = 7
        case .monthly:
            dayCount = 30
        case .quarterly:
            dayCount = 90
        case .yearly:
            dayCount = 365
        }
        return (0..<dayCount).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -(dayCount - 1 - offset), to: today)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: PushupStore
    @State private var logCount: String = ""
    @State private var rangeOption: RangeOption = .weekly
    @State private var showingNotificationAlert = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                    targetSection
                    logSection
                    insightsSection
                    remindersSection
                }
                .padding()
            }
            .navigationTitle("Push Manager")
        }
        .alert("Notifications Disabled", isPresented: $showingNotificationAlert) {
            Button("OK") { }
        } message: {
            Text("Enable notifications in Settings to receive reminders.")
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stay on track with daily pushups.")
                .font(.title2)
                .fontWeight(.semibold)
            HStack(spacing: 16) {
                StatCard(title: "Today", value: "\(store.total(for: Date()))", subtitle: "Target: \(store.dailyTargetTotal())")
                StatCard(title: "Streak", value: "\(store.streak())", subtitle: "days hit target")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text("Daily pushup target: \(store.dailyTarget)")
                    }
                } else {
                    Stepper(value: $store.incrementSize, in: 1...200) {
                        Text("Pushups per set: \(store.incrementSize)")
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

    private var logSection: some View {
        SectionCard(title: "Log pushups") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("Pushups completed", text: $logCount)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Add set") {
                        guard let count = Int(logCount), count > 0 else { return }
                        store.addEntry(count: count)
                        logCount = ""
                    }
                    .buttonStyle(.borderedProminent)
                }

                ProgressView(value: Double(store.total(for: Date())), total: Double(max(store.dailyTargetTotal(), 1)))
                Text("\(store.total(for: Date())) / \(store.dailyTargetTotal())")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if store.entries.filter({ Calendar.current.isDateInToday($0.timestamp) }).isEmpty {
                        Text("No sets logged yet today.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(store.entries.filter { Calendar.current.isDateInToday($0.timestamp) }.reversed()) { entry in
                            HStack {
                                Text("\(entry.count) pushups")
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }

    private var insightsSection: some View {
        SectionCard(title: "Insights") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $rangeOption) {
                    ForEach(RangeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

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

                BarChart(entries: totals)
            }
        }
    }

    private var remindersSection: some View {
        SectionCard(title: "Reminders") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Daily reminder", isOn: $store.reminderEnabled)
                DatePicker("Reminder time", selection: $store.reminderTime, displayedComponents: .hourAndMinute)

                Button("Save reminder") {
                    NotificationScheduler.updateReminder(store: store) { authorized in
                        if !authorized {
                            store.reminderEnabled = false
                            showingNotificationAlert = true
                        }
                        store.save()
                    }
                }
                .buttonStyle(.bordered)

                Text(store.reminderEnabled ? "Reminders set for \(store.reminderTime.formatted(date: .omitted, time: .shortened))." : "Reminders are off.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onChange(of: store.reminderEnabled) { _ in store.save() }
            .onChange(of: store.reminderTime) { _ in store.save() }
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
        .background(Color(.secondarySystemBackground))
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
        .background(Color(.systemBackground))
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
                    Text(entry.date, format: .dateTime.month().day())
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

enum NotificationScheduler {
    static func updateReminder(store: PushupStore, completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if !granted {
                    completion(false)
                    return
                }
                center.removePendingNotificationRequests(withIdentifiers: ["pushup-reminder"])
                guard store.reminderEnabled else {
                    completion(true)
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Push Manager reminder"
                content.body = "Log your pushups to stay on target today."

                let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: store.reminderTime)
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(identifier: "pushup-reminder", content: content, trigger: trigger)
                center.add(request)
                completion(true)
            }
        }
    }
}

