import CoreLocation
import SwiftUI

@main
struct HeroDirtApp: App {
    @StateObject private var placeStore = PlaceStore()
    @StateObject private var mapItemCache = MapItemCache.shared
    private let locationManager = CLLocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(placeStore)
                .environmentObject(mapItemCache)
                .onAppear {
                    locationManager.requestWhenInUseAuthorization()
                }
        }
    }
}
