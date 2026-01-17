//
//  SectionCard.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blueSteel.opacity(0.08))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}
