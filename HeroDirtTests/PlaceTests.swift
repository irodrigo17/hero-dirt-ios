import CoreLocation
import Foundation
import MapKit
import Testing
import SwiftUI

@testable import HeroDirt

struct PlaceTests {

    @MainActor
    @Test func shareContainsOnlyActualImageAndAppStoreDownloadURL() throws {
        let image = try #require(UIImage(systemName: "mountain.2.fill"))
        let items = TrailSharePayload(image: image).activityItems
        #expect(items.count == 2)
        #expect(items[0] as? UIImage === image)
        let url = try #require(items[1] as? URL)
        #expect(url.absoluteString == "https://apps.apple.com/app/id6770195112")
        #expect(url.scheme == "https")
        #expect(url.host == "apps.apple.com")
    }

    private final class ThreadCheckedMapItem: MKMapItem {
        override var url: URL? {
            get {
                #expect(!Thread.isMainThread, "Lazy MapKit website lookup must not block menu rendering")
                return URL(string: "https://example.com/trail")
            }
            set {}
        }
    }

    @MainActor
    @Test func websiteLookupRunsOffMainThread() async {
        let item = ThreadCheckedMapItem(location: CLLocation(latitude: 37, longitude: -122), address: nil)
        #expect(await PlaceWebsite.url(for: item)?.host == "example.com")
    }

    @MainActor
    @Test(arguments: ["https://example.com/trail", "http://example.com/trail"])
    func preparesPlaceWebsite(_ value: String) async throws {
        let item = MKMapItem(location: CLLocation(latitude: 37, longitude: -122), address: nil)
        let url = try #require(URL(string: value))
        item.url = url
        #expect(await PlaceWebsite.url(for: item)?.absoluteString == value)
    }

    @MainActor
    @Test(arguments: ["file:///tmp/trail", "javascript:alert(1)", "herodirt://trail", "https:/trail"])
    func rejectsNonWebsitePlaceURLs(_ value: String) async throws {
        let item = MKMapItem(location: CLLocation(latitude: 37, longitude: -122), address: nil)
        let url = try #require(URL(string: value))
        item.url = url
        #expect(await PlaceWebsite.url(for: item) == nil)
    }

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
        #expect(decoded.destination == original.destination)
    }

    @Test func sharingPrefersApplePlaceIDWithoutCoordinatesOrName() throws {
        let original = SharedTrail(name: "My Custom Trail Name",
                                   coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122),
                                   mapItemID: "I1234567890")
        let components = try #require(URLComponents(url: original.appURL, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "placeID", value: "I1234567890")])
        let parsed = try #require(SharedTrail(url: original.appURL))
        #expect(parsed.destination == .placeID("I1234567890"))
    }

    @Test func blankPlaceIDFallsBackToCoordinates() throws {
        let trail = SharedTrail(name: "Point on map", coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122), mapItemID: "")
        #expect(trail.destination == .coordinates(latitude: 37, longitude: -122))
        #expect(try #require(URLComponents(url: trail.appURL, resolvingAgainstBaseURL: false)).queryItems?.count == 3)
    }

    @MainActor
    @Test func resolvesSharedApplePlaceIDBeforeOpeningDetails() async throws {
        let trail = try #require(SharedTrail(url: URL(string: "herodirt://trail?placeID=I1234567890")!))
        let resolver = LiveSharedTrailResolver(lookup: { identifier in
            #expect(identifier == "I1234567890")
            let item = MKMapItem(location: CLLocation(latitude: 37.5, longitude: -122.5), address: nil)
            item.name = "Resolved Apple Place"
            return item
        })
        let item = try await resolver.resolve(trail)
        #expect(item.name == "Resolved Apple Place")
        #expect(item.location.coordinate.latitude == 37.5)
    }

    @MainActor
    @Test func coordinateShareResolvesWithoutPlaceLookup() async throws {
        let trail = SharedTrail(name: "Dropped Pin", coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122))
        let resolver = LiveSharedTrailResolver(lookup: { _ in
            Issue.record("Coordinate fallback must not request an Apple place ID")
            throw URLError(.resourceUnavailable)
        })
        let item = try await resolver.resolve(trail)
        #expect(item.name == "Dropped Pin")
        #expect(item.location.coordinate.latitude == 37)
        #expect(item.location.coordinate.longitude == -122)
    }

    @Test func unresolvedPlaceIDReportsFailureWithoutInventingCoordinates() async throws {
        let trail = try #require(SharedTrail(url: URL(string: "herodirt://trail?placeID=I1234567890")!))
        let resolver = LiveSharedTrailResolver(lookup: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await resolver.resolve(trail)
            Issue.record("An unresolved ID must fail instead of opening a fabricated destination")
        } catch {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @Test(arguments: [
        "herodirt://trail?lat=91&lon=0",
        "herodirt://trail?lat=0&lon=-181",
        "herodirt://trail?lat=nan&lon=0",
        "herodirt://trail?lat=0&lon=inf",
        "herodirt://trail?lat=1&lat=2&lon=0",
        "herodirt://trail?lat=1",
        "https://example.com/trail?lat=1&lon=2",
        "herodirt://other?lat=1&lon=2",
        "herodirt://trail?placeID=",
        "herodirt://trail?placeID=%20",
        "herodirt://trail?placeID=I1234567890&placeID=I1234567890",
        "herodirt://trail?placeID=I1234567890&lat=1&lon=2",
        "herodirt://trail?placeID=I1234567890&name=Mixed"
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
