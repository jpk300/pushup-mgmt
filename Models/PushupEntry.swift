//
//  PushupEntry.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

struct PushupEntry: Identifiable, Codable {
    let id: UUID
    let count: Int
    let timestamp: Date

    init(id: UUID = UUID(), count: Int, timestamp: Date) {
        self.id = id
        self.count = count
        self.timestamp = timestamp
    }
}
