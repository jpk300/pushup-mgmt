//
//  PushupEntry.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//

import Foundation

struct PushupEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let count: Int
    let timestamp: Date
    let activityType: ActivityType

    init(id: UUID = UUID(), count: Int, timestamp: Date, activityType: ActivityType = .pushups) {
        self.id = id
        self.count = count
        self.timestamp = timestamp
        self.activityType = activityType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        count = try container.decode(Int.self, forKey: .count)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        activityType = (try? container.decode(ActivityType.self, forKey: .activityType)) ?? .pushups
    }

    enum CodingKeys: String, CodingKey {
        case id
        case count
        case timestamp
        case activityType
    }
}
