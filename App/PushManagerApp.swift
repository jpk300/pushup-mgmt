//
//  PushManagerApp.swift
//  Pushup Tracker
//
//  Created by Jason on 1/17/26.
//


import SwiftUI

@main
struct PushManagerApp: App {
    @StateObject private var store = PushupStore()

    var body: some Scene {
        WindowGroup {
            PushManagerView()
                .environmentObject(store)
                .tint(.blueSteel)
                .onAppear {
                    store.load()
                }
        }
    }
}
