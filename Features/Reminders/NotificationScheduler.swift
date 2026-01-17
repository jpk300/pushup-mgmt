import Foundation
import UserNotifications

enum NotificationScheduler {
    struct ReminderSchedule {
        let all: [ReminderTime]
        let filtered: [ReminderTime]
    }

    struct ReminderSnapshot {
        let reminderEnabled: Bool
        let useIntervalReminders: Bool
        let reminderTimes: [ReminderTime]
        let reminderIntervalHours: Int
        let reminderStartTime: Date
        let quietHoursEnabled: Bool
        let quietHoursStart: Date
        let quietHoursEnd: Date
        let onlyRemindIfBehind: Bool
        let behindThresholdType: BehindThresholdType
        let behindThresholdValue: Int
        let totalToday: Int
        let dailyTargetTotal: Int
    }

    static func updateReminder(store: PushupStore, completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        Task {
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                await MainActor.run { completion(false) }
                return
            }
            guard granted else {
                await MainActor.run { completion(false) }
                return
            }

        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix("pushup-reminder-") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await MainActor.run {
            let snapshot = reminderSnapshot(store: store)
            guard snapshot.reminderEnabled,
                    snapshot.useIntervalReminders || !snapshot.reminderTimes.isEmpty else {
                completion(true)
                return
            }
            guard snapshot.totalToday < snapshot.dailyTargetTotal else {
                completion(true)
                return
            }
            guard shouldScheduleBasedOnProgress(snapshot: snapshot) else {
                completion(true)
                return
            }
            let schedule = reminderSchedule(snapshot: snapshot)
            guard !schedule.filtered.isEmpty else {
                completion(true)
                return
            }
            for (index, reminder) in schedule.filtered.enumerated() {
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
            completion(true)
        }
    }
}

    static func reminderSchedule(store: PushupStore) -> ReminderSchedule {
        let snapshot = reminderSnapshot(store: store)
        return reminderSchedule(snapshot: snapshot)
    }

    static func reminderSchedule(snapshot: ReminderSnapshot) -> ReminderSchedule {
        let baseReminders = reminderTimes(snapshot: snapshot)
        let filtered = filteredReminders(reminders: baseReminders, snapshot: snapshot)
        return ReminderSchedule(all: baseReminders, filtered: filtered)
    }

    @MainActor
    private static func reminderSnapshot(store: PushupStore) -> ReminderSnapshot {
        ReminderSnapshot(
            reminderEnabled: store.reminderEnabled,
            useIntervalReminders: store.useIntervalReminders,
            reminderTimes: store.reminderTimes,
            reminderIntervalHours: store.reminderIntervalHours,
            reminderStartTime: store.reminderStartTime,
            quietHoursEnabled: store.quietHoursEnabled,
            quietHoursStart: store.quietHoursStart,
            quietHoursEnd: store.quietHoursEnd,
            onlyRemindIfBehind: store.onlyRemindIfBehind,
            behindThresholdType: store.behindThresholdType,
            behindThresholdValue: store.behindThresholdValue,
            totalToday: store.total(for: Date()),
            dailyTargetTotal: store.dailyTargetTotal()
        )
    }

    private static func reminderTimes(snapshot: ReminderSnapshot) -> [ReminderTime] {
        let baseReminders: [ReminderTime]
        if snapshot.useIntervalReminders {
            baseReminders = intervalReminders(snapshot: snapshot)
        } else {
            baseReminders = snapshot.reminderTimes
        }
        return filterStartTime(reminders: baseReminders, startTime: snapshot.reminderStartTime)
    }

    private static func intervalReminders(snapshot: ReminderSnapshot) -> [ReminderTime] {
        let intervalHours = max(snapshot.reminderIntervalHours, 1)
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(bySettingHour: calendar.component(.hour, from: snapshot.reminderStartTime),
                                  minute: calendar.component(.minute, from: snapshot.reminderStartTime),
                                  second: 0,
                                  of: now) ?? now
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return []
        }
        var reminders: [ReminderTime] = []
        var current = start
        while current < end {
            reminders.append(ReminderTime(time: current))
            guard let next = calendar.date(byAdding: .hour, value: intervalHours, to: current) else {
                break
            }
            current = next
        }
        return reminders
    }

    private static func filterStartTime(reminders: [ReminderTime], startTime: Date) -> [ReminderTime] {
        let calendar = Calendar.current
        let startMinutes = minutesSinceMidnight(for: startTime, calendar: calendar)
        return reminders.filter { reminder in
            minutesSinceMidnight(for: reminder.time, calendar: calendar) >= startMinutes
        }
    }

    private static func filteredReminders(reminders: [ReminderTime], snapshot: ReminderSnapshot) -> [ReminderTime] {
        guard snapshot.quietHoursEnabled else { return reminders }
        return reminders.filter { reminder in
            !isInQuietHours(time: reminder.time, start: snapshot.quietHoursStart, end: snapshot.quietHoursEnd)
        }
    }

    private static func shouldScheduleBasedOnProgress(snapshot: ReminderSnapshot) -> Bool {
        guard snapshot.onlyRemindIfBehind else { return true }
        let total = snapshot.totalToday
        let target = max(snapshot.dailyTargetTotal, 0)
        switch snapshot.behindThresholdType {
        case .percent:
            let percent = max(min(snapshot.behindThresholdValue, 100), 0)
            let threshold = Int(round(Double(target) * Double(percent) / 100.0))
            return total < threshold
        case .count:
            return total < snapshot.behindThresholdValue
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
