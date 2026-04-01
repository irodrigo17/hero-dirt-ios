import Testing
import Foundation
@testable import RainClaude

struct PlaceStoreTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "PlaceStoreTests_\(UUID().uuidString).json")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - CRUD

    @Test func addPlaceIncreasesCount() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        #expect(store.places.isEmpty)

        store.addPlace(Place(name: "A", latitude: 1, longitude: 2))
        #expect(store.places.count == 1)

        store.addPlace(Place(name: "B", latitude: 3, longitude: 4))
        #expect(store.places.count == 2)
    }

    @Test func removePlaceDecreasesCount() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        let place = Place(name: "Remove Me", latitude: 0, longitude: 0)
        store.addPlace(place)
        #expect(store.places.count == 1)

        store.removePlace(place)
        #expect(store.places.isEmpty)
    }

    @Test func renamePlaceUpdatesName() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        let place = Place(name: "Old Name", latitude: 0, longitude: 0)
        store.addPlace(place)

        store.renamePlace(place, to: "New Name")
        #expect(store.places.first?.name == "New Name")
    }

    // MARK: - Proximity search

    @Test func placeNearFindsWithinThreshold() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        let place = Place(name: "Near", latitude: 10.0, longitude: 20.0)
        store.addPlace(place)

        let found = store.placeNear(latitude: 10.0002, longitude: 20.0003)
        #expect(found != nil)
        #expect(found?.id == place.id)
    }

    @Test func placeNearReturnsNilForDistant() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        store.addPlace(Place(name: "Far", latitude: 10.0, longitude: 20.0))

        let found = store.placeNear(latitude: 11.0, longitude: 21.0)
        #expect(found == nil)
    }

    // MARK: - Persistence

    @Test func persistenceAcrossInstances() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store1 = PlaceStore(fileURL: url)
        store1.addPlace(Place(name: "Persisted", latitude: 5, longitude: 10))
        #expect(store1.places.count == 1)

        let store2 = PlaceStore(fileURL: url)
        #expect(store2.places.count == 1)
        #expect(store2.places.first?.name == "Persisted")
    }
}
