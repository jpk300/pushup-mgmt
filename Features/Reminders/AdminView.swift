//
//  AdminView.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var store: PushupStore
    @State private var showingNotificationAlert = false
    @State private var newReminderTime: Date = PushupStore.defaultReminderTime()
    @State private var showingReminderResult = false
    @State private var reminderResultMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                activitySection
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
                Picker("Target type", selection: store.binding(for: \.targetType)) {
                    ForEach(TargetType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if store.binding(for: \.targetType).wrappedValue == .dailyTotal {
                    Stepper(value: store.binding(for: \.dailyTarget), in: 1...1000) {
                        Text("Daily \(store.selectedActivity.noun) target: \(store.binding(for: \.dailyTarget).wrappedValue)")
                    }
                } else {
                    Stepper(value: store.binding(for: \.incrementSize), in: 1...200) {
                        Text("\(store.selectedActivity.title) per set: \(store.binding(for: \.incrementSize).wrappedValue)")
                    }
                    Stepper(value: store.binding(for: \.setsPerDay), in: 1...50) {
                        Text("Sets per day: \(store.binding(for: \.setsPerDay).wrappedValue)")
                    }
                }
            }
            .onChange(of: store.selectedActivity) { store.save() }
        }
    }

    private var activitySection: some View {
        SectionCard(title: "Activity") {
            Picker("Activity", selection: $store.selectedActivity) {
                ForEach(ActivityType.allCases) { activity in
                    Text(activity.title).tag(activity)
                }
            }
            .pickerStyle(.segmented)
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
                        Text("\(store.selectedActivity.title) reminders")
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
                        Toggle("Use interval reminders", isOn: $store.useIntervalReminders)
                        Text("Switch to a cadence if you prefer reminders every few hours instead of fixed times.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if store.useIntervalReminders {
                            Stepper(value: $store.reminderIntervalHours, in: 1...12) {
                                Text("Repeat every \(store.reminderIntervalHours) hour\(store.reminderIntervalHours == 1 ? "" : "s")")
                            }
                            Button("Every 2 hours preset") {
                                store.useIntervalReminders = true
                                store.reminderIntervalHours = 2
                                store.save()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text("Reminder times")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack(spacing: 8) {
                                Button("3x/day") {
                                    setReminderTimes([
                                        reminderTime(hour: 9, minute: 0),
                                        reminderTime(hour: 13, minute: 0),
                                        reminderTime(hour: 18, minute: 0)
                                    ])
                                }
                                .buttonStyle(.bordered)
                                Button("Morning only") {
                                    setReminderTimes([reminderTime(hour: 9, minute: 0)])
                                }
                                .buttonStyle(.bordered)
                            }

                            ForEach($store.reminderTimes) { $reminder in
                                HStack {
                                    DatePicker("Reminder", selection: $reminder.time, displayedComponents: .hourAndMinute)
                                    Button("Remove") {
                                        store.reminderTimes.removeAll { $0.id == reminder.id }
                                        store.save()
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
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Only remind if behind", isOn: $store.onlyRemindIfBehind)
                        if store.onlyRemindIfBehind {
                            Picker("Behind by", selection: $store.behindThresholdType) {
                                ForEach(BehindThresholdType.allCases) { type in
                                    Text(type.label).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            if store.behindThresholdType == .percent {
                                Stepper(value: $store.behindThresholdValue, in: 5...100, step: 5) {
                                    Text("Behind by \(store.behindThresholdValue)% of target")
                                }
                            } else {
                                Stepper(value: $store.behindThresholdValue, in: 1...1000) {
                                    Text("Behind by \(store.behindThresholdValue) \(store.selectedActivity.noun)")
                                }
                            }
                        }
                    }

                    DatePicker("Start reminding after", selection: $store.reminderStartTime, displayedComponents: .hourAndMinute)

                    Toggle("Enable quiet hours", isOn: $store.quietHoursEnabled)
                    if store.quietHoursEnabled {
                        HStack {
                            DatePicker("Quiet hours start", selection: $store.quietHoursStart, displayedComponents: .hourAndMinute)
                            DatePicker("Quiet hours end", selection: $store.quietHoursEnd, displayedComponents: .hourAndMinute)
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
            .onChange(of: store.reminderEnabled) {
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
            .onChange(of: store.quietHoursEnabled) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.useIntervalReminders) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.reminderIntervalHours) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.onlyRemindIfBehind) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.behindThresholdType) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.behindThresholdValue) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.reminderStartTime) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.quietHoursStart) {
                NotificationScheduler.updateReminder(store: store) { _ in
                    store.save()
                }
            }
            .onChange(of: store.quietHoursEnd) {
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
            .onChange(of: store.showMonthly) { store.save() }
            .onChange(of: store.showQuarterly) { store.save() }
            .onChange(of: store.showYearly) { store.save() }
        }
    }

    private func reminderStatusText() -> String {
        guard store.reminderEnabled else {
            return "Reminders are off."
        }
        if store.total(for: Date()) >= store.dailyTargetTotal() {
            return "Reminders paused: target already met."
        }
        let schedule = NotificationScheduler.reminderSchedule(store: store)
        if schedule.all.isEmpty {
            return store.useIntervalReminders ? "Choose an interval to start reminders." : "Add at least one reminder time."
        }
        if schedule.filtered.isEmpty {
            let startSummary = "Start after \(store.reminderStartTime.formatted(DateFormats.reminderTime))"
            let behindSummary = reminderBehindSummary()
            return "All reminders are suppressed by quiet hours. \(startSummary)\(behindSummary)"
        }
        let times = schedule.filtered
            .map { $0.time.formatted(DateFormats.reminderTime) }
            .joined(separator: ", ")
        let suppressedCount = schedule.all.count - schedule.filtered.count
        let behindSummary = reminderBehindSummary()
        let startSummary = "Start after \(store.reminderStartTime.formatted(DateFormats.reminderTime))"
        if store.quietHoursEnabled {
            let quietStart = store.quietHoursStart.formatted(DateFormats.reminderTime)
            let quietEnd = store.quietHoursEnd.formatted(DateFormats.reminderTime)
            let suppressionText = suppressedCount > 0 ? " \(suppressedCount) reminder\(suppressedCount == 1 ? "" : "s") suppressed by quiet hours." : ""
            return "Reminders set for \(times). Quiet hours: \(quietStart)–\(quietEnd).\(suppressionText) \(startSummary)\(behindSummary)"
        }
        let suppressionText = suppressedCount > 0 ? " \(suppressedCount) reminder\(suppressedCount == 1 ? "" : "s") suppressed by quiet hours." : ""
        return "Reminders set for \(times).\(suppressionText) \(startSummary)\(behindSummary)"
    }

    private func reminderBehindSummary() -> String {
        guard store.onlyRemindIfBehind else { return "" }
        switch store.behindThresholdType {
        case .percent:
            return " Only if below \(store.behindThresholdValue)% of target."
        case .count:
            return " Only if below \(store.behindThresholdValue) \(store.selectedActivity.noun)."
        }
    }

    private func setReminderTimes(_ times: [Date]) {
        store.useIntervalReminders = false
        store.reminderTimes = times.map { ReminderTime(time: $0) }.sorted { $0.time < $1.time }
        store.save()
    }

    private func reminderTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
