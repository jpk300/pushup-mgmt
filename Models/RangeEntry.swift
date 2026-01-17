//
//  RangeEntry.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

struct RangeEntry: Identifiable {
    let id = UUID()
    let date: Date
    let total: Int
}
