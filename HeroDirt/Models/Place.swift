import Foundation
import MapKit
import CoreLocation

struct Place: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var mapItemId: MKMapItem.Identifier?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, mapItemId: MKMapItem.Identifier? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemId = mapItemId
    }
}
