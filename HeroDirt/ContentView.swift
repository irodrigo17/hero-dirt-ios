import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var pendingPlace: Place? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            MapExploreView(pendingPlace: $pendingPlace)
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(0)
            SavedPlacesView()
                .tabItem {
                    Label("Saved", systemImage: "star.fill")
                }
                .tag(1)
        }
    }
}
