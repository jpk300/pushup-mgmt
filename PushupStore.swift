import Combine
import SwiftUI

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

    static func defaultReminderStartTime() -> Date {
        Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
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
        targetType = payload.targetType
        dailyTarget = payload.dailyTarget
        incrementSize = payload.incrementSize
        setsPerDay = payload.setsPerDay
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
        targetType: TargetType,
        dailyTarget: Int,
        incrementSize: Int,
        setsPerDay: Int,
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
        self.targetType = targetType
        self.dailyTarget = dailyTarget
        self.incrementSize = incrementSize
        self.setsPerDay = setsPerDay
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
        targetType = try container.decode(TargetType.self, forKey: .targetType)
        dailyTarget = try container.decode(Int.self, forKey: .dailyTarget)
        incrementSize = try container.decode(Int.self, forKey: .incrementSize)
        setsPerDay = try container.decode(Int.self, forKey: .setsPerDay)
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
        try container.encode(targetType, forKey: .targetType)
        try container.encode(dailyTarget, forKey: .dailyTarget)
        try container.encode(incrementSize, forKey: .incrementSize)
        try container.encode(setsPerDay, forKey: .setsPerDay)
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
    }
}
//
//  PushupStore.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//

