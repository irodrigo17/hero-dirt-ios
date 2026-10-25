import CoreLocation
import Foundation
import MapKit

/// Share links carry an Apple Maps identifier or a destination, never a private saved-place ID.
struct SharedTrail: Identifiable, Sendable {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6770195112")!

    enum Destination: Equatable, Sendable {
        case placeID(String)
        case coordinates(latitude: Double, longitude: Double)
    }

    let id = UUID()
    let name: String
    let destination: Destination

    init(name: String, coordinate: CLLocationCoordinate2D, mapItemID: String? = nil) {
        self.name = String(name.prefix(200))
        if let mapItemID, Self.validPlaceID(mapItemID) {
            destination = .placeID(mapItemID)
        } else {
            destination = .coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "herodirt",
              components.host?.lowercased() == "trail",
              components.path.isEmpty || components.path == "/" else { return nil }
        let items = components.queryItems ?? []
        func value(_ key: String) -> String? {
            let matches = items.filter { $0.name == key }
            return matches.count == 1 ? matches[0].value : nil
        }
        if items.contains(where: { $0.name == "placeID" }) {
            guard let placeID = value("placeID"), Self.validPlaceID(placeID),
                  !items.contains(where: { ["lat", "lon", "name"].contains($0.name) }) else { return nil }
            destination = .placeID(placeID)
            name = "Shared Trail"
        } else {
            guard let lat = value("lat").flatMap(Double.init),
                  let lon = value("lon").flatMap(Double.init),
                  lat.isFinite, lon.isFinite,
                  (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            let title = (value("name") ?? "Shared Trail").trimmingCharacters(in: .whitespacesAndNewlines)
            name = title.isEmpty ? "Shared Trail" : String(title.prefix(200))
            destination = .coordinates(latitude: lat, longitude: lon)
        }
    }

    private static func validPlaceID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 512 &&
            value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil &&
            MKMapItem.Identifier(rawValue: value) != nil
    }

    var appURL: URL {
        var url = URLComponents()
        url.scheme = "herodirt"
        url.host = "trail"
        switch destination {
        case .placeID(let identifier):
            url.queryItems = [URLQueryItem(name: "placeID", value: identifier)]
        case .coordinates(let latitude, let longitude):
            url.queryItems = [
                URLQueryItem(name: "lat", value: String(latitude)),
                URLQueryItem(name: "lon", value: String(longitude)),
                URLQueryItem(name: "name", value: name)
            ]
        }
        return url.url!
    }

    func message(condition: String) -> String {
        "\(name) — \(condition)\nTrail conditions estimated by Hero Dirt.\n\nOpen in Hero Dirt: \(appURL.absoluteString)\nGet Hero Dirt: \(Self.appStoreURL.absoluteString)"
    }
}

protocol SharedTrailResolving: Sendable {
    func resolve(_ trail: SharedTrail) async throws -> MKMapItem
}

struct LiveSharedTrailResolver: SharedTrailResolving {
    var lookup: @Sendable (String) async throws -> MKMapItem = { value in
        guard let identifier = MKMapItem.Identifier(rawValue: value) else { throw URLError(.badURL) }
        return try await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
    }

    func resolve(_ trail: SharedTrail) async throws -> MKMapItem {
        switch trail.destination {
        case .placeID(let identifier):
            return try await lookup(identifier)
        case .coordinates(let latitude, let longitude):
            let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
            item.name = trail.name
            return item
        }
    }
}
