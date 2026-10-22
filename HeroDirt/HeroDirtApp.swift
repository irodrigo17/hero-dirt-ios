import CoreLocation
import SwiftUI

@main
struct HeroDirtApp: App {
    /// `-useFakeServices`: run on sample data with no network or iCloud
    /// (UI tests, screenshots, demos).
    private static let useFakeServices = ProcessInfo.processInfo.arguments.contains("-useFakeServices")

    private static let weather: any WeatherProviding =
        useFakeServices ? FakeWeatherProvider() : LiveWeatherProvider()
    private static let soil: any SoilProviding =
        useFakeServices ? FakeSoilProvider() : LiveSoilProvider()

    @State private var placeStore = useFakeServices ? SampleData.placeStore() : PlaceStore()
    @State private var mapItemCache = MapItemCache()
    @AppStorage(RainUnitPreference.storageKey) private var unitPreference = RainUnitPreference.automatic
    private let locationManager = CLLocationManager()

    init() {
        Telemetry.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(placeStore)
                .environment(mapItemCache)
                .environment(\.rainUnit, unitPreference.resolved())
                .environment(\.weather, Self.weather)
                .environment(\.soil, Self.soil)
                .onAppear {
                    locationManager.requestWhenInUseAuthorization()
                }
        }
    }
}
