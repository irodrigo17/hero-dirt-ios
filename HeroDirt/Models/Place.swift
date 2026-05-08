import CoreLocation
import Foundation
import MapKit

struct Place: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var mapItemIdString: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var mapItemId: MKMapItem.Identifier? {
        guard let rawValue = mapItemIdString else { return nil }
        return MKMapItem.Identifier(rawValue: rawValue)
    }

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        mapItemId: MKMapItem.Identifier? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemIdString = mapItemId?.rawValue
    }
}
