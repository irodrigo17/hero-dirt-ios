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
