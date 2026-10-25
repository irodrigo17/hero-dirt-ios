import MapKit
import SwiftUI

extension MKPointOfInterestCategory {
    var displayName: String {
        switch self {
        case .amusementPark: return String(localized: "Amusement Park")
        case .aquarium: return String(localized: "Aquarium")
        case .atm: return String(localized: "ATM")
        case .bakery: return String(localized: "Bakery")
        case .bank: return String(localized: "Bank")
        case .beach: return String(localized: "Beach")
        case .brewery: return String(localized: "Brewery")
        case .cafe: return String(localized: "Café")
        case .campground: return String(localized: "Campground")
        case .carRental: return String(localized: "Car Rental")
        case .evCharger: return String(localized: "EV Charger")
        case .fireStation: return String(localized: "Fire Station")
        case .fitnessCenter: return String(localized: "Fitness Center")
        case .foodMarket: return String(localized: "Food Market")
        case .gasStation: return String(localized: "Gas Station")
        case .hospital: return String(localized: "Hospital")
        case .hotel: return String(localized: "Hotel")
        case .laundry: return String(localized: "Laundry")
        case .library: return String(localized: "Library")
        case .marina: return String(localized: "Marina")
        case .movieTheater: return String(localized: "Movie Theater")
        case .museum: return String(localized: "Museum")
        case .nationalPark: return String(localized: "National Park")
        case .nightlife: return String(localized: "Nightlife")
        case .park: return String(localized: "Park")
        case .parking: return String(localized: "Parking")
        case .pharmacy: return String(localized: "Pharmacy")
        case .police: return String(localized: "Police")
        case .postOffice: return String(localized: "Post Office")
        case .publicTransport: return String(localized: "Public Transport")
        case .restaurant: return String(localized: "Restaurant")
        case .restroom: return String(localized: "Restroom")
        case .school: return String(localized: "School")
        case .stadium: return String(localized: "Stadium")
        case .store: return String(localized: "Store")
        case .theater: return String(localized: "Theater")
        case .university: return String(localized: "University")
        case .winery: return String(localized: "Winery")
        case .zoo: return String(localized: "Zoo")
        default:
            // Unknown/new MapKit categories have no app-owned translation.
            // Keep a localized fallback instead of exposing a raw API name.
            return String(localized: "Place")
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

    var iconColor: Color {
        switch self {
        case .park, .nationalPark, .campground, .zoo:
            return .green
        case .hiking:
            return Color(red: 0.2, green: 0.6, blue: 0.2)
        case .beach, .marina:
            return .teal
        case .restaurant, .foodMarket, .bakery:
            return .orange
        case .cafe, .brewery, .winery:
            return Color(red: 0.6, green: 0.3, blue: 0.1)
        case .nightlife, .movieTheater, .theater, .museum, .amusementPark:
            return .purple
        case .hospital, .pharmacy, .fireStation:
            return .red
        case .hotel, .publicTransport, .parking, .store, .carRental, .evCharger,
            .police, .postOffice, .laundry, .marina:
            return .blue
        case .school, .university, .library:
            return Color(red: 0.5, green: 0.35, blue: 0.1)
        case .fitnessCenter, .stadium:
            return Color(red: 0.9, green: 0.4, blue: 0.0)
        case .gasStation, .atm, .bank, .restroom:
            return Color(.systemGray)
        default:
            return Color(.systemPink)
        }
    }
}
