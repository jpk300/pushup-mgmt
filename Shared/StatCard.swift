//
//  StatCard.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blueSteel.opacity(0.15))
        .cornerRadius(16)
    }
}
