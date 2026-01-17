//
//  LineChart.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

struct LineChart: View {
    let entries: [ChartEntry]

    var body: some View {
        let values = entries.map { $0.value }
        let maxValue = max(values.max() ?? 1, 1)
        let minValue = min(values.min() ?? 0, maxValue)
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let step = entries.count > 1 ? width / CGFloat(entries.count - 1) : 0
            let range = max(maxValue - minValue, 1)
            let points = entries.enumerated().map { index, entry in
                let x = CGFloat(index) * step
                let normalized = (entry.value - minValue) / range
                let y = height - CGFloat(normalized) * height
                return CGPoint(x: x, y: y)
            }

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.blue, lineWidth: 2)

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
        }
        .frame(height: 180)
    }
}
