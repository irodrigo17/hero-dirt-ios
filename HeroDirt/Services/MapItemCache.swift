import Foundation
import MapKit
import Observation

/// MapKit place details (category, address) for saved places, fetched by
/// their stored map item identifier.
@MainActor
@Observable
final class MapItemCache {
    private(set) var items: [UUID: MKMapItem] = [:]
    @ObservationIgnored private var inFlight: [UUID: Task<MKMapItem?, Never>] = [:]

    init(items: [UUID: MKMapItem] = [:]) {
        self.items = items
    }

    @discardableResult
    func fetch(for place: Place) async -> MKMapItem? {
        if let cached = items[place.id] { return cached }
        guard let mapItemId = place.mapItemId else { return nil }
        if let task = inFlight[place.id] { return await task.value }
        let id = place.id
        let task = Task<MKMapItem?, Never> {
            let item = try? await MKMapItemRequest(mapItemIdentifier: mapItemId).mapItem
            self.inFlight[id] = nil
            if let item { self.items[id] = item }
            return item
        }
        inFlight[id] = task
        return await task.value
    }

    func prefetch(places: [Place]) {
        for place in places {
            guard place.mapItemId != nil,
                  items[place.id] == nil,
                  inFlight[place.id] == nil
            else { continue }
            Task { await self.fetch(for: place) }
        }
    }
}
