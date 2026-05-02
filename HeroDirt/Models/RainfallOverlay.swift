import Foundation
import CoreLocation

struct RainfallCell: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let latDelta: Double
    let lonDelta: Double
    let summary: RainfallSummary

    var polygon: [CLLocationCoordinate2D] {
        let halfLat = latDelta / 2
        let halfLon = lonDelta / 2
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        return [
            CLLocationCoordinate2D(latitude: lat - halfLat, longitude: lon - halfLon),
            CLLocationCoordinate2D(latitude: lat - halfLat, longitude: lon + halfLon),
            CLLocationCoordinate2D(latitude: lat + halfLat, longitude: lon + halfLon),
            CLLocationCoordinate2D(latitude: lat + halfLat, longitude: lon - halfLon),
        ]
    }
}

enum RainfallTimeframe: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case twoDays = "2d"
    case threeDays = "3d"
    case sevenDays = "7d"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneDay: return "1 Day"
        case .twoDays: return "2 Days"
        case .threeDays: return "3 Days"
        case .sevenDays: return "7 Days"
        }
    }

    func amount(from summary: RainfallSummary) -> Double {
        switch self {
        case .oneDay: return summary.last1Day
        case .twoDays: return summary.last2Days
        case .threeDays: return summary.last3Days
        case .sevenDays: return summary.last7Days
        }
    }
}
