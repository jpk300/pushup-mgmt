import Combine
import SwiftUI

@MainActor
final class PushupStore: ObservableObject {
    @Published var selectedActivity: ActivityType = .pushups
    @Published private var activitySettings: [ActivityType: ActivitySettings] = [
        .pushups: ActivitySettings.defaults(for: .pushups),
        .situps: ActivitySettings.defaults(for: .situps)
    ]
    @Published var entries: [PushupEntry] = [] {
        didSet {
            recalculateDailyTotals()
        }
    }
    @Published var reminderEnabled: Bool = false
    @Published var reminderTimes: [ReminderTime] = [ReminderTime(time: PushupStore.defaultReminderTime())]
    @Published var useIntervalReminders: Bool = false
    @Published var reminderIntervalHours: Int = 2
    @Published var onlyRemindIfBehind: Bool = false
    @Published var behindThresholdType: BehindThresholdType = .percent
    @Published var behindThresholdValue: Int = 25
    @Published var reminderStartTime: Date = PushupStore.defaultReminderStartTime()
    @Published var quietHoursEnabled: Bool = false
    @Published var quietHoursStart: Date = PushupStore.defaultQuietHoursStart()
    @Published var quietHoursEnd: Date = PushupStore.defaultQuietHoursEnd()
    @Published var showMonthly: Bool = true
    @Published var showQuarterly: Bool = true
    @Published var showYearly: Bool = true
    private let storageKey = "pushManagerStore"
    private var dailyTotalsCache: [ActivityType: [Date: Int]] = [:]
    
    static func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    }
    
    static func defaultQuietHoursStart() -> Date {
        Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    }
    
    static func defaultQuietHoursEnd() -> Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    }
    
    static func defaultReminderStartTime() -> Date {
        Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    }
    
    func dailyTargetTotal(activity: ActivityType? = nil) -> Int {
        let activityType = activity ?? selectedActivity
        let settings = settings(for: activityType)
        return settings.targetType == .incremental ? settings.incrementSize * settings.setsPerDay : settings.dailyTarget
    }
    
    func addEntry(count: Int, activity: ActivityType? = nil) {
        let activityType = activity ?? selectedActivity
        entries.append(PushupEntry(count: count, timestamp: Date(), activityType: activityType))

        func trimOldEntries() {
            let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
            entries = entries.filter { $0.timestamp >= cutoff }
        }

        save()
        guard reminderEnabled else { return }
        NotificationScheduler.updateReminder(store: self) { _ in }
    }
    
    func updateEntry(id: UUID, count: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let activityType = entries[index].activityType
        entries[index] = PushupEntry(id: id, count: count, timestamp: entries[index].timestamp, activityType: activityType)
        save()
        guard reminderEnabled else { return }
        NotificationScheduler.updateReminder(store: self) { _ in }
    }
    
    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
        guard reminderEnabled else { return }
        NotificationScheduler.updateReminder(store: self) { _ in }
    }
    
    
    func total(for day: Date, activity: ActivityType? = nil) -> Int {
        let activityType = activity ?? selectedActivity
        let dayStart = Calendar.current.startOfDay(for: day)
        return dailyTotalsCache[activityType]?[dayStart] ?? 0
    }
    
    func streak(activity: ActivityType? = nil) -> Int {
        let activityType = activity ?? selectedActivity
        let target = dailyTargetTotal(activity: activityType)
        guard target > 0 else { return 0 }
        
        let calendar = Calendar.current
        var current = Date()
        var days = 0
        while true {
                    if isRestDay(current, activity: activityType) {
                        guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else {
                            break
                        }
                        current = previous
                        continue
            }
            if total(for: current, activity: activityType) >= target {
                            days += 1
                            guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else {
                                break
                            }
                            current = previous
                            continue
                        }
            if calendar.isDateInToday(current) {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else {
                    break
                }
                current = previous
                continue
            }
                        break
        }
        return days
    }
    
    func isRestDay(_ date: Date, activity: ActivityType? = nil) -> Bool {
        let activityType = activity ?? selectedActivity
        let settings = settings(for: activityType)
        let restDays = Set(settings.restDays.map { Calendar.current.startOfDay(for: $0) })
        return restDays.contains(Calendar.current.startOfDay(for: date))
    }

    func setRestDay(_ date: Date, isRestDay: Bool, activity: ActivityType? = nil) {
        let activityType = activity ?? selectedActivity
        let day = Calendar.current.startOfDay(for: date)
        updateSettings(for: activityType) { settings in
            var restDays = Set(settings.restDays.map { Calendar.current.startOfDay(for: $0) })
            if isRestDay {
                restDays.insert(day)
            } else {
                restDays.remove(day)
            }
            settings.restDays = Array(restDays)
        }
    }

    func totals(for range: RangeOption, activity: ActivityType? = nil) -> [RangeEntry] {
        let activityType = activity ?? selectedActivity
        return range.dates().map { date in
            RangeEntry(date: date, total: total(for: date, activity: activityType), isRestDay: isRestDay(date, activity: activityType))
        }
    }

    func averagePerDay(for range: RangeOption, activity: ActivityType? = nil) -> Int {
        let activityType = activity ?? selectedActivity
        let dates = range.dates()
        let nonRestDates = dates.filter { !isRestDay($0, activity: activityType) }
        let sum = nonRestDates.reduce(0) { partial, date in
            partial + total(for: date, activity: activityType)
        }
        guard !nonRestDates.isEmpty else { return 0 }
        return Int(round(Double(sum) / Double(nonRestDates.count)))
    }
    
    func chartEntries(for range: RangeOption, activity: ActivityType? = nil) -> [ChartEntry] {
        let activityType = activity ?? selectedActivity
        switch range {
        case .daily, .weekly, .monthly:
            return totals(for: range, activity: activityType).map { entry in
                ChartEntry(date: entry.date, value: Double(entry.total))
            }
        case .quarterly:
            return averagedEntries(range: range, bucketSize: 7, activity: activityType)
        case .yearly:
            return averagedEntries(range: range, bucketSize: 14, activity: activityType)
        }
    }

    func personalRecordSingleSet(activity: ActivityType? = nil) -> Int {
        let activityType = activity ?? selectedActivity
        return entries
            .filter { $0.activityType == activityType }
            .map(\.count)
            .max() ?? 0
    }

    func personalRecordDay(activity: ActivityType? = nil) -> Int {
        let activityType = activity ?? selectedActivity
        let totals = dailyTotalsCache[activityType] ?? [:]
        return totals.values.max() ?? 0
    }
    
    private func averagedEntries(range: RangeOption, bucketSize: Int, activity: ActivityType) -> [ChartEntry] {
        let dates = range.dates()
        guard !dates.isEmpty else { return [] }
        var results: [ChartEntry] = []
        var index = 0
        while index < dates.count {
            let end = min(index + bucketSize, dates.count)
            let bucket = dates[index..<end]
            let nonRestDates = bucket.filter { !isRestDay($0, activity: activity) }
            let sum = nonRestDates.reduce(0) { partial, date in
                partial + total(for: date, activity: activity)
            }
            let average = nonRestDates.isEmpty ? 0 : Double(sum) / Double(nonRestDates.count)
            if let bucketDate = bucket.last {
                results.append(ChartEntry(date: bucketDate, value: average))
            }
            index = end
        }
        return results
    }
    
    func save() {
        let payload = StorePayload(
            selectedActivity: selectedActivity,
            activitySettings: activitySettings,
            entries: entries,
            reminderEnabled: reminderEnabled,
            reminderTimes: reminderTimes,
            useIntervalReminders: useIntervalReminders,
            reminderIntervalHours: reminderIntervalHours,
            onlyRemindIfBehind: onlyRemindIfBehind,
            behindThresholdType: behindThresholdType,
            behindThresholdValue: behindThresholdValue,
            reminderStartTime: reminderStartTime,
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
        selectedActivity = payload.selectedActivity
        activitySettings = payload.activitySettings
        entries = payload.entries
        reminderEnabled = payload.reminderEnabled
        reminderTimes = payload.reminderTimes
        useIntervalReminders = payload.useIntervalReminders
        reminderIntervalHours = payload.reminderIntervalHours
        onlyRemindIfBehind = payload.onlyRemindIfBehind
        behindThresholdType = payload.behindThresholdType
        behindThresholdValue = payload.behindThresholdValue
        reminderStartTime = payload.reminderStartTime
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
        var totalsByActivity: [ActivityType: [Date: Int]] = [:]
        let grouped = Dictionary(grouping: entries, by: { $0.activityType })
        for (activity, activityEntries) in grouped {
            totalsByActivity[activity] = Dictionary(grouping: activityEntries, by: { Calendar.current.startOfDay(for: $0.timestamp) })
                .mapValues { $0.reduce(0) { $0 + $1.count } }
        }
        dailyTotalsCache = totalsByActivity
    }

    func settings(for activity: ActivityType) -> ActivitySettings {
        activitySettings[activity] ?? ActivitySettings.defaults(for: activity)
    }

    func updateSettings(for activity: ActivityType, update: (inout ActivitySettings) -> Void) {
        var settings = activitySettings[activity] ?? ActivitySettings.defaults(for: activity)
        update(&settings)
        activitySettings[activity] = settings
        objectWillChange.send()
        save()
    }

    func binding<T>(for keyPath: WritableKeyPath<ActivitySettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings(for: self.selectedActivity)[keyPath: keyPath] },
            set: { newValue in
                self.updateSettings(for: self.selectedActivity) { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

}

struct StorePayload: Codable {
    var selectedActivity: ActivityType
    var activitySettings: [ActivityType: ActivitySettings]
    var entries: [PushupEntry]
    var reminderEnabled: Bool
    var reminderTimes: [ReminderTime]
    var useIntervalReminders: Bool
    var reminderIntervalHours: Int
    var onlyRemindIfBehind: Bool
    var behindThresholdType: BehindThresholdType
    var behindThresholdValue: Int
    var reminderStartTime: Date
    var quietHoursEnabled: Bool
    var quietHoursStart: Date
    var quietHoursEnd: Date
    var showMonthly: Bool
    var showQuarterly: Bool
    var showYearly: Bool
    
    init(
        selectedActivity: ActivityType,
        activitySettings: [ActivityType: ActivitySettings],
        entries: [PushupEntry],
        reminderEnabled: Bool,
        reminderTimes: [ReminderTime],
        useIntervalReminders: Bool,
        reminderIntervalHours: Int,
        onlyRemindIfBehind: Bool,
        behindThresholdType: BehindThresholdType,
        behindThresholdValue: Int,
        reminderStartTime: Date,
        quietHoursEnabled: Bool,
        quietHoursStart: Date,
        quietHoursEnd: Date,
        showMonthly: Bool,
        showQuarterly: Bool,
        showYearly: Bool
    ) {
        self.selectedActivity = selectedActivity
        self.activitySettings = activitySettings
        self.entries = entries
        self.reminderEnabled = reminderEnabled
        self.reminderTimes = reminderTimes
        self.useIntervalReminders = useIntervalReminders
        self.reminderIntervalHours = reminderIntervalHours
        self.onlyRemindIfBehind = onlyRemindIfBehind
        self.behindThresholdType = behindThresholdType
        self.behindThresholdValue = behindThresholdValue
        self.reminderStartTime = reminderStartTime
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.showMonthly = showMonthly
        self.showQuarterly = showQuarterly
        self.showYearly = showYearly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedActivity = (try? container.decode(ActivityType.self, forKey: .selectedActivity)) ?? .pushups
        if let decodedSettings = try? container.decode([ActivityType: ActivitySettings].self, forKey: .activitySettings) {
            activitySettings = decodedSettings
        } else {
            let legacyTargetType = (try? container.decode(TargetType.self, forKey: .targetType)) ?? .dailyTotal
            let legacyDailyTarget = (try? container.decode(Int.self, forKey: .dailyTarget)) ?? 50
            let legacyIncrementSize = (try? container.decode(Int.self, forKey: .incrementSize)) ?? 10
            let legacySetsPerDay = (try? container.decode(Int.self, forKey: .setsPerDay)) ?? 5
            activitySettings = [
                .pushups: ActivitySettings(
                    targetType: legacyTargetType,
                    dailyTarget: legacyDailyTarget,
                    incrementSize: legacyIncrementSize,
                    setsPerDay: legacySetsPerDay,
                    restDays: (try? container.decode([Date].self, forKey: .restDays)) ?? []
                ),
                .situps: ActivitySettings.defaults(for: .situps)
            ]
        }
        entries = try container.decode([PushupEntry].self, forKey: .entries)
        reminderEnabled = try container.decode(Bool.self, forKey: .reminderEnabled)
        useIntervalReminders = (try? container.decode(Bool.self, forKey: .useIntervalReminders)) ?? false
        reminderIntervalHours = (try? container.decode(Int.self, forKey: .reminderIntervalHours)) ?? 2
        onlyRemindIfBehind = (try? container.decode(Bool.self, forKey: .onlyRemindIfBehind)) ?? false
        behindThresholdType = (try? container.decode(BehindThresholdType.self, forKey: .behindThresholdType)) ?? .percent
        behindThresholdValue = (try? container.decode(Int.self, forKey: .behindThresholdValue)) ?? 25
        reminderStartTime = (try? container.decode(Date.self, forKey: .reminderStartTime)) ?? PushupStore.defaultReminderStartTime()
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
        try container.encode(selectedActivity, forKey: .selectedActivity)
        try container.encode(activitySettings, forKey: .activitySettings)
        try container.encode(entries, forKey: .entries)
        try container.encode(reminderEnabled, forKey: .reminderEnabled)
        try container.encode(reminderTimes, forKey: .reminderTimes)
        try container.encode(useIntervalReminders, forKey: .useIntervalReminders)
        try container.encode(reminderIntervalHours, forKey: .reminderIntervalHours)
        try container.encode(onlyRemindIfBehind, forKey: .onlyRemindIfBehind)
        try container.encode(behindThresholdType, forKey: .behindThresholdType)
        try container.encode(behindThresholdValue, forKey: .behindThresholdValue)
        try container.encode(reminderStartTime, forKey: .reminderStartTime)
        try container.encode(quietHoursEnabled, forKey: .quietHoursEnabled)
        try container.encode(quietHoursStart, forKey: .quietHoursStart)
        try container.encode(quietHoursEnd, forKey: .quietHoursEnd)
        try container.encode(showMonthly, forKey: .showMonthly)
        try container.encode(showQuarterly, forKey: .showQuarterly)
        try container.encode(showYearly, forKey: .showYearly)
    }

    enum CodingKeys: String, CodingKey {
        case selectedActivity
        case activitySettings
        case targetType
        case dailyTarget
        case incrementSize
        case setsPerDay
        case entries
        case reminderEnabled
        case reminderTimes
        case reminderTime
        case useIntervalReminders
        case reminderIntervalHours
        case onlyRemindIfBehind
        case behindThresholdType
        case behindThresholdValue
        case reminderStartTime
        case quietHoursEnabled
        case quietHoursStart
        case quietHoursEnd
        case showMonthly
        case showQuarterly
        case showYearly
        case restDays
    }
}
