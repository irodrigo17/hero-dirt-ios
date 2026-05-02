import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            MapExploreView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
            SavedPlacesView()
                .tabItem {
                    Label("Places", systemImage: "star.fill")
                }
        }
    }
}
