//
//  BarChart.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

struct BarChart: View {
    let entries: [RangeEntry]

    var body: some View {
        let maxValue = max(entries.map { $0.total }.max() ?? 1, 1)
        VStack(spacing: 10) {
            ForEach(entries.suffix(10)) { entry in
                HStack {
                    Text(entry.date, format: DateFormats.chartDay)
                        .font(.caption)
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(entry.isRestDay ? Color.gray.opacity(0.2) : Color.blue.opacity(0.2))
                            if !entry.isRestDay {
                                Capsule().fill(Color.blue)
                                    .frame(width: geometry.size.width * CGFloat(entry.total) / CGFloat(maxValue))
                            }
                        }
                    }
                    .frame(height: 8)
                    Text(entry.isRestDay ? "RD" : "\(entry.total)")
                        .font(.caption)
                        .frame(width: 32, alignment: .trailing)
                }
                .frame(height: 18)
            }
        }
    }
}
