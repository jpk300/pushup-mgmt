//
//  ActivitySettings.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//

import Foundation

struct ActivitySettings: Codable {
    var targetType: TargetType
    var dailyTarget: Int
    var incrementSize: Int
    var setsPerDay: Int
    var restDays: [Date]

    static func defaults(for activity: ActivityType) -> ActivitySettings {
        switch activity {
        case .pushups:
            return ActivitySettings(
                targetType: .dailyTotal,
                dailyTarget: 50,
                incrementSize: 10,
                setsPerDay: 5,
                restDays: []
            )
        case .situps:
            return ActivitySettings(
                targetType: .dailyTotal,
                dailyTarget: 40,
                incrementSize: 15,
                setsPerDay: 4,
                restDays: []
            )
        }
    }
}
