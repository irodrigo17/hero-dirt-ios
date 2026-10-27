import Foundation
import Observation

/// Loads rain (and missing soil) for the saved places list. Kept out of the
/// view so loading, errors and cancellation can be unit tested with fake
/// services.
@MainActor
@Observable
final class PlaceConditionsModel {
    private(set) var rainfall: [UUID: RainfallSummary] = [:]
    private(set) var loading: Set<UUID> = []
    private(set) var errors: [UUID: String] = [:]

    @ObservationIgnored private var soilTask: Task<Void, Never>?

    /// Loads rain for any place that doesn't have it yet. Safe to call
    /// repeatedly: `.task(id:)` restarts this whenever the list changes or
    /// the view is rebuilt (e.g. folding/unfolding), and a cancelled load is
    /// picked up again on the next call.
    func load(_ places: [Place], weather: any WeatherProviding) async {
        let toLoad = places.filter { rainfall[$0.id] == nil }
        guard !toLoad.isEmpty else { return }
        for place in toLoad {
            loading.insert(place.id)
            errors[place.id] = nil
        }

        await withTaskGroup(of: (UUID, Result<RainfallSummary, Error>).self) { group in
            for place in toLoad {
                group.addTask {
                    do {
                        return (place.id, .success(
                            try await weather.rainfall(latitude: place.latitude, longitude: place.longitude)
                        ))
                    } catch {
                        return (place.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let summary):
                    rainfall[id] = summary
                    errors[id] = nil
                    loading.remove(id)
                case .failure(let error):
                    if Task.isCancelled || Self.isCancellation(error) { continue }
                    errors[id] = Self.friendlyMessage(for: error)
                    loading.remove(id)
                }
            }
        }
    }

    /// The soil used for a place's estimate: the user's override, then the
    /// stored SoilGrids lookup (nil means estimated loam).
    static func soil(for place: Place) -> SoilData? {
        place.soilOverride?.asSoilData ?? place.soil
    }

    func condition(for place: Place) -> DirtCondition? {
        rainfall[place.id]?.dirtCondition(soil: Self.soil(for: place))
    }

    /// Current conditions for every place that has data, by place id.
    func conditions(for places: [Place]) -> [UUID: DirtCondition] {
        var result: [UUID: DirtCondition] = [:]
        for place in places {
            if let condition = condition(for: place) { result[place.id] = condition }
        }
        return result
    }

    /// Pull to refresh: drop cached data and load everything again.
    func refresh(_ places: [Place], weather: any WeatherProviding) async {
        for place in places {
            await weather.invalidate(latitude: place.latitude, longitude: place.longitude)
        }
        rainfall = [:]
        errors = [:]
        await load(places, weather: weather)
    }

    /// Looks up soil for places that don't have it yet (saved by older
    /// builds) and stores it on the place. Lookups are throttled by the soil
    /// service, so this runs in the background.
    func backfillSoil(_ places: [Place], soil: any SoilProviding, store: PlaceStore) {
        let missing = places.filter { $0.soil == nil && $0.soilOverride == nil }
        guard !missing.isEmpty, soilTask == nil else { return }
        soilTask = Task {
            for place in missing {
                if let result = await soil.soil(latitude: place.latitude, longitude: place.longitude) {
                    store.updateSoil(result, for: place.id)
                }
            }
            soilTask = nil
        }
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    nonisolated static func friendlyMessage(for error: Error, includeRetryHint: Bool = true) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return includeRetryHint ? String(localized: "You're offline. Pull down to try again.") : String(localized: "You're offline.")
            case .timedOut:
                return includeRetryHint ? String(localized: "The weather service is slow right now. Pull down to try again.") : String(localized: "The weather service is slow right now.")
            default:
                break
            }
        }
        if let weatherError = error as? WeatherService.WeatherError,
           case .httpError(429) = weatherError
        {
            return String(localized: "Too many requests. Try again in a minute.")
        }
        if let weatherError = error as? WeatherService.WeatherError,
           case .rateLimited = weatherError {
            return weatherError.localizedDescription
        }
        return includeRetryHint ? String(localized: "Couldn't load conditions. Pull down to try again.") : String(localized: "Couldn't load conditions.")
    }
}
