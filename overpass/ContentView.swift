//
//  ContentView.swift
//  gastrack
//
//  Created by Kieran Klukas on 3/26/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NearbyView()
                .tabItem { Label("Nearby", systemImage: "fuelpump") }

            MapStationsView()
                .tabItem { Label("Map", systemImage: "map") }

            PrefetchView()
                .tabItem { Label("Route", systemImage: "road.lanes") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(APIClient.shared)
        .environmentObject(EIAService.shared)
}
