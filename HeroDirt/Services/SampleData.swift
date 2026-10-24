import Foundation
import MapKit
import SwiftUI

// Canned data and fake services for SwiftUI previews, UI tests and unit
// tests. Launch the app with `-useFakeServices` to run it entirely on this
// data (no network, no iCloud).

enum SampleData {
    /// Observed days (newest first, ending today) followed by forecast days
    /// (oldest first, starting tomorrow).
    static func days(_ amounts: [Double], forecast: [Double] = [], et0: Double = 3) -> [DailyWeatherData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let past = amounts.enumerated().map { i, amount in
            DailyWeatherData(date: calendar.date(byAdding: .day, value: -i, to: today)!, amount: amount, et0: et0)
        }
        let future = forecast.enumerated().map { i, amount in
            DailyWeatherData(
                date: calendar.date(byAdding: .day, value: i + 1, to: today)!,
                amount: amount, et0: et0, isForecast: true
            )
        }
        return past + future
    }

    private static let dryMonth = Array(repeating: 0.0, count: 25)

    /// Rained a few days ago, drying nicely: hero dirt, rain midweek.
    static let heroDirt = RainfallSummary(daily: days([0, 0, 0, 14, 6] + dryMonth, forecast: [0, 0, 0, 0, 9, 3, 0]))
    /// Raining today, dry week ahead: hero dirt in a few days.
    static let muddy = RainfallSummary(daily: days([12, 4] + dryMonth + [0, 0, 0], forecast: [0, 0, 0, 0, 0, 0, 0]))
    /// Weeks without rain until a storm this weekend.
    static let dusty = RainfallSummary(daily: days(Array(repeating: 0, count: 30), forecast: [0, 0, 14, 4, 0, 0, 0], et0: 5))
    /// Big storm, more on the way.
    static let soaked = RainfallSummary(daily: days([28, 22, 6] + dryMonth + [0, 0], forecast: [10, 4, 0, 0, 0, 0, 0], et0: 2))
    /// Last rain a week ago: firm and fast.
    static let dry = RainfallSummary(daily: days([0, 0, 0, 0, 0, 0, 8] + dryMonth, forecast: [0, 0, 0, 0, 0, 0, 0], et0: 4))

    static let forecast = RainForecast(next1Day: 0, next2Days: 2.5, next3Days: 6, next7Days: 11)

    static let loam = SoilData(sandFraction: 0.4, clayFraction: 0.2)

    private static func place(_ n: Int, _ name: String, _ lat: Double, _ lon: Double) -> Place {
        Place(
            id: UUID(uuidString: String(format: "%08d-0000-0000-0000-000000000000", n))!,
            name: name, latitude: lat, longitude: lon, soil: loam
        )
    }

    static let places: [Place] = [
        place(1, "Rancho San Antonio", 37.3326, -122.0882),
        place(2, "Arastradero Preserve", 37.3866, -122.1797),
        place(3, "Skeggs Point", 37.4136, -122.3033),
        place(4, "Demo Forest", 37.0965, -121.9620),
        place(5, "China Camp", 38.0010, -122.4730),
    ]

    /// A place with a category and website, plus places without websites,
    /// so previews and UI tests can cover both detail-menu states offline.
    @MainActor
    static func mapItemCache() -> MapItemCache {
        let place = places[0]
        let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        item.name = place.name
        item.pointOfInterestCategory = .park
        item.url = URL(string: "https://example.com/trail")
        return MapItemCache(items: [place.id: item])
    }

    /// Which sample weather each sample place gets (for previews/screenshots).
    static func summary(latitude: Double, longitude: Double) -> RainfallSummary {
        let table: [(Double, Double, RainfallSummary)] = [
            (37.3326, -122.0882, heroDirt),
            (37.3866, -122.1797, muddy),
            (37.4136, -122.3033, dusty),
            (37.0965, -121.9620, dry),
            (38.0010, -122.4730, soaked),
        ]
        if let match = table.first(where: { abs($0.0 - latitude) < 0.01 && abs($0.1 - longitude) < 0.01 }) {
            return match.2
        }
        let samples = [heroDirt, muddy, dusty, dry, soaked]
        let index = abs(Int((latitude * 1000).rounded()) + Int((longitude * 1000).rounded())) % samples.count
        return samples[index]
    }

    /// A store holding `places`, persisted to a temporary file.
    @MainActor
    static func placeStore(_ places: [Place] = places) -> PlaceStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "sample_places_\(UUID().uuidString).json")
        try? JSONEncoder().encode(places).write(to: url)
        return PlaceStore(fileURL: url)
    }
}

/// Deterministic weather: picks a sample summary from the coordinate.
struct FakeWeatherProvider: WeatherProviding {
    var delay: Duration = .zero
    var failure: (any Error)? = nil

    func rainfall(latitude: Double, longitude: Double) async throws -> RainfallSummary {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        return SampleData.summary(latitude: latitude, longitude: longitude)
    }

    func forecast(latitude: Double, longitude: Double) async throws -> RainForecast {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        return SampleData.forecast
    }

    func invalidate(latitude: Double, longitude: Double) async {}
}

struct FakeSoilProvider: SoilProviding {
    var result: SoilData? = SampleData.loam

    func soil(latitude: Double, longitude: Double) async -> SoilData? { result }
}

struct FakeDrivingTimeProvider: DrivingTimeProviding {
    var seconds: TimeInterval? = 25 * 60

    func travelTime(to destination: CLLocationCoordinate2D) async -> TimeInterval? { seconds }
}

extension View {
    /// Previews: fake services plus a sample place store.
    @MainActor
    func previewEnvironment(store: PlaceStore? = nil) -> some View {
        self
            .environment(store ?? SampleData.placeStore())
            .environment(SampleData.mapItemCache())
            .environment(PlaceConditionsModel())
            .environment(\.drivingTime, FakeDrivingTimeProvider())
            .environment(\.weather, FakeWeatherProvider())
            .environment(\.soil, FakeSoilProvider())
    }
}
