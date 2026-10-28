import CoreLocation
import SwiftUI

@main
struct HeroDirtApp: App {
    /// `-useFakeServices`: run on sample data with no network or iCloud
    /// (UI tests, screenshots, demos).
    private static let useFakeServices = ProcessInfo.processInfo.arguments.contains("-useFakeServices")

    private static let weather: any WeatherProviding =
        useFakeServices ? FakeWeatherProvider(
            forecastDelay: ProcessInfo.processInfo.arguments.contains("-slowForecast") ? .seconds(60) : .zero
        ) : LiveWeatherProvider()
    private static let drivingTime: any DrivingTimeProviding = useFakeServices
        ? FakeDrivingTimeProvider(
            seconds: ProcessInfo.processInfo.arguments.contains("-noDrivingETA") ? nil : 25 * 60,
            delay: ProcessInfo.processInfo.arguments.contains("-slowDrivingETA") ? .seconds(3) : .zero
        )
        : LiveDrivingTimeProvider()
    private static let sharedTrailResolver: any SharedTrailResolving =
        useFakeServices ? FakeSharedTrailResolver() : LiveSharedTrailResolver()
    private static let soil: any SoilProviding =
        useFakeServices ? FakeSoilProvider() : LiveSoilProvider()

    @State private var placeStore = useFakeServices ? SampleData.placeStore() : PlaceStore()
    @State private var mapItemCache = useFakeServices ? SampleData.mapItemCache() : MapItemCache()
    @State private var conditions = PlaceConditionsModel()
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
                .environment(conditions)
                .environment(\.rainUnit, unitPreference.resolved())
                .environment(\.sharedTrailResolver, Self.sharedTrailResolver)
                .environment(\.weather, Self.weather)
                .environment(\.soil, Self.soil)
                .environment(\.drivingTime, Self.drivingTime)
                .onAppear {
                    locationManager.requestWhenInUseAuthorization()
                }
        }
    }
}
