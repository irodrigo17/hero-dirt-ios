import Foundation
import SwiftUI

// Canned data and fake services for SwiftUI previews, UI tests and unit
// tests. Launch the app with `-useFakeServices` to run it entirely on this
// data (no network, no iCloud).

enum SampleData {
    static func days(_ amounts: [Double], et0: Double = 3) -> [DailyWeatherData] {
        let today = Calendar.current.startOfDay(for: Date())
        return amounts.enumerated().map { i, amount in
            DailyWeatherData(
                date: Calendar.current.date(byAdding: .day, value: -i, to: today)!,
                amount: amount,
                et0: et0
            )
        }
    }

    /// Rained a few days ago, drying nicely: hero dirt.
    static let heroDirt = RainfallSummary(daily: days([0, 0, 0, 14, 6] + Array(repeating: 0, count: 25)))
    /// Raining today.
    static let muddy = RainfallSummary(daily: days([12, 4] + Array(repeating: 0, count: 28)))
    /// Weeks without rain.
    static let dusty = RainfallSummary(daily: days(Array(repeating: 0, count: 30), et0: 5))

    static let forecast = RainForecast(next1Day: 0, next2Days: 2.5, next3Days: 6, next7Days: 11)

    static let loam = SoilData(sandFraction: 0.4, clayFraction: 0.2)

    static let places: [Place] = [
        Place(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Rancho San Antonio", latitude: 37.3326, longitude: -122.0882, soil: loam
        ),
        Place(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Arastradero Preserve", latitude: 37.3866, longitude: -122.1797, soil: loam
        ),
        Place(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Skeggs Point", latitude: 37.4136, longitude: -122.3033, soil: loam
        ),
    ]

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
        let samples = [SampleData.heroDirt, SampleData.muddy, SampleData.dusty]
        let index = abs(Int((latitude * 1000).rounded()) + Int((longitude * 1000).rounded())) % samples.count
        return samples[index]
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

extension View {
    /// Previews: fake services plus a sample place store.
    @MainActor
    func previewEnvironment(store: PlaceStore? = nil) -> some View {
        self
            .environment(store ?? SampleData.placeStore())
            .environment(MapItemCache())
            .environment(PlaceConditionsModel())
            .environment(\.weather, FakeWeatherProvider())
            .environment(\.soil, FakeSoilProvider())
    }
}
