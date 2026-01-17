//
//  DateFormats.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import Foundation

enum DateFormats {
    static let reminderTime = Date.FormatStyle(date: .omitted, time: .shortened)
    static let chartDay = Date.FormatStyle.dateTime.month().day()
}
