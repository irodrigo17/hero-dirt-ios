import Testing
import Foundation
import CoreLocation
@testable import RainClaude

struct PlaceTests {

    @Test func codableRoundTrip() throws {
        let original = Place(name: "Test Place", latitude: -34.6, longitude: -58.4)

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
}
