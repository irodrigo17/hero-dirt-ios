import CoreLocation
import Foundation
import MapKit
import Testing

@testable import HeroDirt

struct PlaceTests {

    @Test func codableRoundTrip() throws {
        let original = Place(
            name: "Test Place",
            latitude: -34.6,
            longitude: -58.4
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Place.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.latitude == original.latitude)
        #expect(decoded.longitude == original.longitude)
    }

    @Test func coordinateProperty() {
        let place = Place(name: "Test", latitude: 40.7128, longitude: -74.006)
        let coord = place.coordinate

        #expect(coord.latitude == 40.7128)
        #expect(coord.longitude == -74.006)
    }

    @Test func customID() {
        let customID = UUID()
        let place = Place(id: customID, name: "Test", latitude: 0, longitude: 0)

        #expect(place.id == customID)
    }

    @Test func defaultID() {
        let place = Place(name: "Test", latitude: 0, longitude: 0)

        #expect(place.id != UUID())
    }

    @Test func hashableEquality() {
        let placeID = UUID()
        let place1 = Place(id: placeID, name: "A", latitude: 1, longitude: 2)
        let place2 = Place(id: placeID, name: "A", latitude: 1, longitude: 2)

        #expect(place1 == place2)
        #expect(place1.hashValue == place2.hashValue)
    }

    @Test func sendableConformance() {
        let place = Place(name: "Test", latitude: 1, longitude: 2)

        func checkSendable(_: some Sendable) {}
        checkSendable(place)
    }
}
