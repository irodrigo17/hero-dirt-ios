import Foundation
import MapKit

@MainActor
final class MapItemCache: ObservableObject {
    static let shared = MapItemCache()

    @Published private(set) var items: [UUID: MKMapItem] = [:]
    private var inFlight: [UUID: Task<MKMapItem?, Never>] = [:]

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
