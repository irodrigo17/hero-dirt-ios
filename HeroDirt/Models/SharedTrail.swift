import CoreLocation
import Foundation

/// Share links carry a destination, never a private saved-place identifier.
struct SharedTrail: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = String(name.prefix(200))
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "herodirt",
              components.host?.lowercased() == "trail",
              components.path.isEmpty || components.path == "/" else { return nil }
        func value(_ key: String) -> String? {
            let matches = (components.queryItems ?? []).filter { $0.name == key }
            return matches.count == 1 ? matches[0].value : nil
        }
        guard let lat = value("lat").flatMap(Double.init),
              let lon = value("lon").flatMap(Double.init),
              lat.isFinite, lon.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        let title = (value("name") ?? "Shared Trail").trimmingCharacters(in: .whitespacesAndNewlines)
        name = title.isEmpty ? "Shared Trail" : String(title.prefix(200))
        latitude = lat
        longitude = lon
    }

    var appURL: URL {
        var url = URLComponents()
        url.scheme = "herodirt"
        url.host = "trail"
        url.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "name", value: name)
        ]
        return url.url!
    }

    /// Apple Maps opens this HTTPS link even when Hero Dirt isn't installed.
    var mapsURL: URL {
        var url = URLComponents(string: "https://maps.apple.com/")!
        url.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name)
        ]
        return url.url!
    }

    func message(condition: String) -> String {
        "\(name) — \(condition)\nTrail conditions estimated by Hero Dirt.\n\nView location: \(mapsURL.absoluteString)\nOpen in Hero Dirt: \(appURL.absoluteString)"
    }
}
