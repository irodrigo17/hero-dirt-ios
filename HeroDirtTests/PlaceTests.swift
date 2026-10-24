import CoreLocation
import Foundation
import MapKit
import Testing
import SwiftUI

@testable import HeroDirt

struct PlaceTests {

    @MainActor
    @Test func sharingCardRendersAnExportableImage() throws {
        let renderer = ImageRenderer(content: TrailSharingCard(
            name: "Rancho San Antonio", summary: SampleData.heroDirt, soil: SampleData.loam,
            sharedAt: Date(timeIntervalSince1970: 1792843200)
        ).environment(\.rainUnit, .millimeters))
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        #expect(image.size.width == 420)
        #expect(image.size.height > 300)
        let png = try #require(image.pngData())
        #expect(png.count > 1000)
        let path = FileManager.default.temporaryDirectory.appending(path: "trail-share-snapshot.png")
        try png.write(to: path)
        print("Share image snapshot: \(path.path)")
    }

    @Test func sharedTrailLinksRoundTripNamesAndCoordinates() throws {
        let original = SharedTrail(name: "Ridge & Creek / North #1", coordinate: CLLocationCoordinate2D(latitude: 37.3326, longitude: -122.0882))
        let decoded = try #require(SharedTrail(url: original.appURL))
        #expect(decoded.name == original.name)
        #expect(decoded.latitude == original.latitude)
        #expect(decoded.longitude == original.longitude)
        let maps = try #require(URLComponents(url: original.mapsURL, resolvingAgainstBaseURL: false))
        #expect(maps.scheme == "https")
        #expect(maps.host == "maps.apple.com")
        #expect(maps.queryItems?.first(where: { $0.name == "q" })?.value == original.name)
    }

    @Test(arguments: [
        "herodirt://trail?lat=91&lon=0",
        "herodirt://trail?lat=0&lon=-181",
        "herodirt://trail?lat=nan&lon=0",
        "herodirt://trail?lat=0&lon=inf",
        "herodirt://trail?lat=1&lat=2&lon=0",
        "herodirt://trail?lat=1",
        "https://example.com/trail?lat=1&lon=2",
        "herodirt://other?lat=1&lon=2"
    ]) func invalidSharedTrailIsRejected(_ value: String) {
        #expect(SharedTrail(url: URL(string: value)!) == nil)
    }

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
