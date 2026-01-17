//
//  ChartEntry.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

struct ChartEntry: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
