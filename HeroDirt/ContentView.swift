import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MapExploreView()
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
