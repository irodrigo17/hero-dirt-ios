import MapKit
import UIKit

extension MKPointOfInterestCategory {
    var displayName: String {
        switch self {
        case .amusementPark: return "Amusement Park"
        case .aquarium: return "Aquarium"
        case .atm: return "ATM"
        case .bakery: return "Bakery"
        case .bank: return "Bank"
        case .beach: return "Beach"
        case .brewery: return "Brewery"
        case .cafe: return "Café"
        case .campground: return "Campground"
        case .carRental: return "Car Rental"
        case .evCharger: return "EV Charger"
        case .fireStation: return "Fire Station"
        case .fitnessCenter: return "Fitness Center"
        case .foodMarket: return "Food Market"
        case .gasStation: return "Gas Station"
        case .hospital: return "Hospital"
        case .hotel: return "Hotel"
        case .laundry: return "Laundry"
        case .library: return "Library"
        case .marina: return "Marina"
        case .movieTheater: return "Movie Theater"
        case .museum: return "Museum"
        case .nationalPark: return "National Park"
        case .nightlife: return "Nightlife"
        case .park: return "Park"
        case .parking: return "Parking"
        case .pharmacy: return "Pharmacy"
        case .police: return "Police"
        case .postOffice: return "Post Office"
        case .publicTransport: return "Public Transport"
        case .restaurant: return "Restaurant"
        case .restroom: return "Restroom"
        case .school: return "School"
        case .stadium: return "Stadium"
        case .store: return "Store"
        case .theater: return "Theater"
        case .university: return "University"
        case .winery: return "Winery"
        case .zoo: return "Zoo"
        default:
            let raw = rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
            return raw.unicodeScalars.reduce("") { result, scalar in
                let char = Character(scalar)
                return result.isEmpty ? String(char) : char.isUppercase ? "\(result) \(char)" : "\(result)\(char)"
            }
        }
    }

    var sfSymbol: String {
        switch self {
        case .amusementPark: return "ferriswheel"
        case .aquarium: return "fish.fill"
        case .atm: return "banknote.fill"
        case .bakery: return "birthday.cake.fill"
        case .bank: return "building.columns.fill"
        case .beach: return "beach.umbrella.fill"
        case .brewery: return "mug.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .campground: return "tent.fill"
        case .carRental: return "car.fill"
        case .evCharger: return "bolt.car.fill"
        case .fireStation: return "flame.fill"
        case .fitnessCenter: return "figure.run"
        case .foodMarket: return "basket.fill"
        case .gasStation: return "fuelpump.fill"
        case .hospital: return "cross.fill"
        case .hotel: return "bed.double.fill"
        case .laundry: return "washer.fill"
        case .library: return "books.vertical.fill"
        case .marina: return "sailboat.fill"
        case .movieTheater: return "film.fill"
        case .museum: return "building.columns.fill"
        case .nationalPark: return "tree.fill"
        case .nightlife: return "moon.stars.fill"
        case .park: return "tree.fill"
        case .parking: return "p.circle.fill"
        case .pharmacy: return "pills.fill"
        case .police: return "shield.fill"
        case .postOffice: return "envelope.fill"
        case .publicTransport: return "tram.fill"
        case .restaurant: return "fork.knife"
        case .restroom: return "toilet.fill"
        case .school: return "graduationcap.fill"
        case .stadium: return "sportscourt.fill"
        case .store: return "cart.fill"
        case .theater: return "theatermasks.fill"
        case .university: return "building.columns.fill"
        case .winery: return "wineglass.fill"
        case .zoo: return "pawprint.fill"
        default: return "mappin"
        }
    }

    var iconColor: UIColor {
        switch self {
        case .park, .nationalPark, .campground, .zoo:
            return .systemGreen
        case .hiking:
            return UIColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1)
        case .beach, .marina:
            return .systemTeal
        case .restaurant, .foodMarket, .bakery:
            return .systemOrange
        case .cafe, .brewery, .winery:
            return UIColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1)
        case .nightlife, .movieTheater, .theater, .museum, .amusementPark:
            return .systemPurple
        case .hospital, .pharmacy, .fireStation:
            return .systemRed
        case .hotel, .publicTransport, .parking, .store, .carRental, .evCharger,
            .police, .postOffice, .laundry:
            return .systemBlue
        case .school, .university, .library:
            return UIColor(red: 0.5, green: 0.35, blue: 0.1, alpha: 1)
        case .fitnessCenter, .stadium:
            return UIColor(red: 0.9, green: 0.4, blue: 0.0, alpha: 1)
        case .gasStation, .atm, .bank, .restroom:
            return .systemGray
        default:
            return .systemPink
        }
    }
}
