//
//  BehindThresholdType.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

enum BehindThresholdType: String, CaseIterable, Codable, Identifiable {
    case percent
    case count

    var id: String { rawValue }

    var label: String {
        switch self {
        case .percent:
            return "Percent of target"
        case .count:
            return "Rep count"
        }
    }
}
