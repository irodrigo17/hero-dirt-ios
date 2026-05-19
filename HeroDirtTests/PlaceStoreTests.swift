import Foundation
import Testing

@testable import HeroDirt

@MainActor
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

    // MARK: - removePlaces(at:)

    @Test func removePlacesAtOffsets() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        store.addPlace(Place(name: "A", latitude: 1, longitude: 1))
        store.addPlace(Place(name: "B", latitude: 2, longitude: 2))
        store.addPlace(Place(name: "C", latitude: 3, longitude: 3))
        #expect(store.places.count == 3)

        store.removePlaces(at: IndexSet(integer: 1))
        #expect(store.places.count == 2)
        #expect(store.places.map(\.name) == ["A", "C"])
    }

    @Test func removePlacesMultipleOffsets() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        store.addPlace(Place(name: "A", latitude: 1, longitude: 1))
        store.addPlace(Place(name: "B", latitude: 2, longitude: 2))
        store.addPlace(Place(name: "C", latitude: 3, longitude: 3))

        store.removePlaces(at: IndexSet([0, 2]))
        #expect(store.places.count == 1)
        #expect(store.places.first?.name == "B")
    }

    @Test func removePlacesEmptyIndexSet() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        store.addPlace(Place(name: "A", latitude: 1, longitude: 1))

        store.removePlaces(at: IndexSet())
        #expect(store.places.count == 1)
    }

    // MARK: - Proximity search edge cases

    @Test func placeNearExactMatch() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        let place = Place(name: "Exact", latitude: 10.0, longitude: 20.0)
        store.addPlace(place)

        let found = store.placeNear(latitude: 10.0, longitude: 20.0)
        #expect(found?.id == place.id)
    }

    @Test func placeNearMultipleReturnsFirst() {
        let url = makeTempURL()
        defer { cleanup(url) }

        let store = PlaceStore(fileURL: url)
        let placeA = Place(name: "A", latitude: 10.0, longitude: 20.0)
        let placeB = Place(name: "B", latitude: 10.0001, longitude: 20.0001)
        store.addPlace(placeA)
        store.addPlace(placeB)

        let found = store.placeNear(latitude: 10.0, longitude: 20.0)
        #expect(found?.id == placeA.id)
    }

    // MARK: - Error handling

    @Test func loadCorruptedJSON() {
        let url = makeTempURL()
        defer { cleanup(url) }

        try? "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = PlaceStore(fileURL: url)
        #expect(store.places.isEmpty)
    }

    @Test func loadMissingFile() {
        let url = makeTempURL()

        let store = PlaceStore(fileURL: url)
        #expect(store.places.isEmpty)
    }
}
