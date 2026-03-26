//
//  gastrackApp.swift
//  gastrack
//
//  Created by Kieran Klukas on 3/26/26.
//

import SwiftUI

@main
struct gastrackApp: App {
    @StateObject private var api = APIClient.shared
    @StateObject private var eia = EIAService.shared
    @StateObject private var store = StationStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
                .environmentObject(eia)
                .environmentObject(store)
                .task { await eia.load(api: api) }
        }
    }
}
