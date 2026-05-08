import CoreLocation
import SwiftUI

@main
struct HeroDirtApp: App {
    @StateObject private var placeStore = PlaceStore()
    private let locationManager = CLLocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(placeStore)
                .onAppear {
                    locationManager.requestWhenInUseAuthorization()
                }
        }
    }
}
