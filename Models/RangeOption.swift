//
//  RangeOption.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

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
