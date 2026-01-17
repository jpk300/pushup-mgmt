//
//  ReminderTime.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

struct ReminderTime: Identifiable, Codable, Hashable {
    let id: UUID
    var time: Date

    init(id: UUID = UUID(), time: Date) {
        self.id = id
        self.time = time
    }
}
