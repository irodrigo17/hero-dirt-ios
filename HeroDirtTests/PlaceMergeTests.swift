import Foundation
import Testing

@testable import HeroDirt

struct PlaceMergeTests {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func place(_ id: UUID, _ name: String, updated: TimeInterval? = nil) -> Place {
        Place(
            id: id, name: name, latitude: 1, longitude: 2,
            updatedAt: updated.map { Date(timeIntervalSince1970: $0) }
        )
    }

    @Test func restoresRemotePlacesIntoEmptyLocal() {
        let remote = [place(a, "A"), place(b, "B")]
        let merged = PlaceStore.merge(local: [], remote: remote, deleted: [])
        #expect(merged.map(\.id) == [a, b])
    }

    @Test func keepsLocalOnlyPlaces() {
        // A place saved while iCloud was unreachable must not be lost when an
        // older remote copy arrives.
        let merged = PlaceStore.merge(
            local: [place(a, "A"), place(c, "C")],
            remote: [place(a, "A"), place(b, "B")],
            deleted: []
        )
        #expect(Set(merged.map(\.id)) == [a, b, c])
        #expect(merged.first?.id == a)  // local order preserved
    }

    @Test func newestCopyWins() {
        let merged = PlaceStore.merge(
            local: [place(a, "Old name", updated: 100)],
            remote: [place(a, "New name", updated: 200)],
            deleted: []
        )
        #expect(merged.map(\.name) == ["New name"])

        let merged2 = PlaceStore.merge(
            local: [place(a, "Local edit", updated: 300)],
            remote: [place(a, "Stale", updated: 200)],
            deleted: []
        )
        #expect(merged2.map(\.name) == ["Local edit"])
    }

    @Test func tombstonesPreventResurrection() {
        let merged = PlaceStore.merge(
            local: [place(a, "A")],
            remote: [place(a, "A"), place(b, "Deleted elsewhere")],
            deleted: [b]
        )
        #expect(merged.map(\.id) == [a])
    }

    @Test func dropsDuplicates() {
        let merged = PlaceStore.merge(
            local: [place(a, "A"), place(a, "A again")],
            remote: [place(a, "A")],
            deleted: []
        )
        #expect(merged.count == 1)
    }

    @Test func oldSavedDataWithoutTimestampStillDecodes() throws {
        let json = #"[{"id":"11111111-1111-1111-1111-111111111111","name":"Old","latitude":1,"longitude":2}]"#
        let places = try JSONDecoder().decode([Place].self, from: Data(json.utf8))
        #expect(places.first?.updatedAt == nil)
    }
}

@MainActor
struct PlaceStoreSyncTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sync_\(UUID().uuidString).json")
    }

    @Test func restoresFromKeyValueStoreAfterReinstall() {
        // Same iCloud key-value store, fresh install (no backup file).
        let kvs = InMemoryKeyValueStore()
        let first = PlaceStore(kvs: kvs, backupURL: tempURL(), observeICloud: false)
        first.addPlace(Place(name: "Skeggs", latitude: 37.4, longitude: -122.3))

        let reinstalled = PlaceStore(kvs: kvs, backupURL: tempURL(), observeICloud: false)
        #expect(reinstalled.places.map(\.name) == ["Skeggs"])
    }

    @Test func migratesFromBackupWhenKeyValueStoreIsEmpty() {
        // First launch after updating from the file-only version.
        let url = tempURL()
        let old = PlaceStore(fileURL: url)
        old.addPlace(Place(name: "Old", latitude: 1, longitude: 2))

        let kvs = InMemoryKeyValueStore()
        let updated = PlaceStore(kvs: kvs, backupURL: url, observeICloud: false)
        #expect(updated.places.map(\.name) == ["Old"])
        #expect(kvs.data(forKey: "places.v1") != nil)
    }

    @Test func deletionsSyncAsTombstones() {
        let kvs = InMemoryKeyValueStore()
        let a = PlaceStore(kvs: kvs, backupURL: tempURL(), observeICloud: false)
        let place = Place(name: "Gone", latitude: 1, longitude: 2)
        a.addPlace(place)
        let backupWithPlace = tempURL()
        try? JSONEncoder().encode(a.places).write(to: backupWithPlace)
        a.removePlace(place)

        // A device whose backup still has the place must not resurrect it.
        let b = PlaceStore(kvs: kvs, backupURL: backupWithPlace, observeICloud: false)
        b.mergeIn([place])
        #expect(b.places.isEmpty)
    }

    @Test func updateSoilPersists() {
        let kvs = InMemoryKeyValueStore()
        let store = PlaceStore(kvs: kvs, backupURL: tempURL(), observeICloud: false)
        let place = Place(name: "P", latitude: 1, longitude: 2)
        store.addPlace(place)
        let soil = SoilData(sandFraction: 0.7, clayFraction: 0.1)
        store.updateSoil(soil, for: place.id)

        let reopened = PlaceStore(kvs: kvs, backupURL: tempURL(), observeICloud: false)
        #expect(reopened.places.first?.soil == soil)
    }
}

@MainActor
struct PlaceStoreMoveTests {
    @Test func movePersistsNewOrder() {
        let url = FileManager.default.temporaryDirectory.appending(path: "move_\(UUID().uuidString).json")
        let store = PlaceStore(fileURL: url)
        for name in ["A", "B", "C"] { store.addPlace(Place(name: name, latitude: 1, longitude: 1)) }
        store.movePlaces(from: IndexSet(integer: 2), to: 0)
        #expect(store.places.map(\.name) == ["C", "A", "B"])
        #expect(PlaceStore(fileURL: url).places.map(\.name) == ["C", "A", "B"])
    }
}
