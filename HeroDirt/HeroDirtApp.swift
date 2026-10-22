import CoreLocation
import SwiftUI

@main
struct HeroDirtApp: App {
    @StateObject private var placeStore = PlaceStore()
    @StateObject private var mapItemCache = MapItemCache.shared
    @AppStorage(RainUnitPreference.storageKey) private var unitPreference = RainUnitPreference.automatic
    private let locationManager = CLLocationManager()

    init() {
        Telemetry.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(placeStore)
                .environmentObject(mapItemCache)
                .environment(\.rainUnit, unitPreference.resolved())
                .onAppear {
                    locationManager.requestWhenInUseAuthorization()
                }
        }
    }
}
