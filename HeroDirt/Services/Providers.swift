import Foundation
import SwiftUI

// Service seams. Views talk to these protocols through the environment
// instead of calling static services directly, so previews, UI tests and
// unit tests can swap in fakes.

protocol WeatherProviding: Sendable {
    /// Observed daily rain and ET0 for roughly the last 30 days.
    func rainfall(latitude: Double, longitude: Double) async throws -> RainfallSummary
    /// Rain forecast for the next 7 days.
    func forecast(latitude: Double, longitude: Double) async throws -> RainForecast
    /// Drops cached data for a location (pull to refresh).
    func invalidate(latitude: Double, longitude: Double) async
}

protocol SoilProviding: Sendable {
    /// Soil texture for a location, or nil if it couldn't be looked up.
    func soil(latitude: Double, longitude: Double) async -> SoilData?
}

// MARK: - Live implementations

struct LiveWeatherProvider: WeatherProviding {
    func rainfall(latitude: Double, longitude: Double) async throws -> RainfallSummary {
        try await WeatherService.fetchRainfall(latitude: latitude, longitude: longitude)
    }

    func forecast(latitude: Double, longitude: Double) async throws -> RainForecast {
        try await WeatherService.fetchRainForecast(latitude: latitude, longitude: longitude)
    }

    func invalidate(latitude: Double, longitude: Double) async {
        await WeatherService.cache.invalidate(key: WeatherCache.key(latitude: latitude, longitude: longitude))
    }
}

struct LiveSoilProvider: SoilProviding {
    func soil(latitude: Double, longitude: Double) async -> SoilData? {
        await SoilService.fetchSoilData(latitude: latitude, longitude: longitude)
    }
}

extension SoilProviding {
    /// The soil to use for a location: the user's override, then the place's
    /// stored soil, then a lookup, then estimated loam.
    func resolve(override: SoilOverride?, stored: SoilData?, latitude: Double, longitude: Double) async -> SoilData {
        if let override { return override.asSoilData }
        if let stored { return stored }
        return await soil(latitude: latitude, longitude: longitude) ?? .loam
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var sharedTrailResolver: any SharedTrailResolving = LiveSharedTrailResolver()
    @Entry var weather: any WeatherProviding = LiveWeatherProvider()
    @Entry var drivingTime: any DrivingTimeProviding = LiveDrivingTimeProvider()
    @Entry var soil: any SoilProviding = LiveSoilProvider()
}

/// Bounds the primary conditions request, including time waiting for a request
/// slot. URLSession and the request budget both cooperate with cancellation.
enum WeatherRequestDeadline {
    static func run<T: Sendable>(timeout: Duration = .seconds(25),
                                 operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
