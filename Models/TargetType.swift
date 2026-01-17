//
//  TargetType.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

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
