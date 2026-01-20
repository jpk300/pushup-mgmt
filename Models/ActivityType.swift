//
//  ActivityType.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//

import Foundation

enum ActivityType: String, CaseIterable, Identifiable, Codable {
    case pushups
    case situps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushups:
            return "Push-Ups"
        case .situps:
            return "Sit-Ups"
        }
    }

    var noun: String {
        switch self {
        case .pushups:
            return "push-ups"
        case .situps:
            return "sit-ups"
        }
    }

    var reminderTitle: String {
        switch self {
        case .pushups:
            return "Push-up Manager reminder"
        case .situps:
            return "Sit-up Manager reminder"
        }
    }

    var reminderBody: String {
        "Log your \(noun) to stay on target today."
    }
}
