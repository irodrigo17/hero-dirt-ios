import CoreLocation
import Foundation
import MapKit

struct Place: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var mapItemIdString: String?
    var soilOverride: SoilOverride?
    /// Last local modification, used for last-writer-wins when merging copies
    /// from iCloud. Optional so older saved data still decodes.
    var updatedAt: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    @MainActor var mapItem: MKMapItem? { MapItemCache.shared.items[id] }

    var mapItemId: MKMapItem.Identifier? {
        guard let rawValue = mapItemIdString else { return nil }
        return MKMapItem.Identifier(rawValue: rawValue)
    }

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        mapItemId: MKMapItem.Identifier? = nil,
        soilOverride: SoilOverride? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemIdString = mapItemId?.rawValue
        self.soilOverride = soilOverride
        self.updatedAt = updatedAt
    }
}
