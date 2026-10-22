import MapKit
import Observation
import SwiftUI

/// What the place details screen is showing. One value instead of a handful
/// of optionals that could disagree.
enum Selection: Equatable {
    /// A saved place.
    case saved(UUID)
    /// A point of interest tapped on the map.
    case mapItem(MKMapItem)
    /// A search result (gets its own pin on the map).
    case searchResult(MKMapItem)
    /// A pin dropped with a long press (or a place that was just unsaved).
    case droppedPin(CLLocationCoordinate2D, name: String?)

    static func == (lhs: Selection, rhs: Selection) -> Bool {
        switch (lhs, rhs) {
        case let (.saved(a), .saved(b)): return a == b
        case let (.mapItem(a), .mapItem(b)): return a == b
        case let (.searchResult(a), .searchResult(b)): return a == b
        case let (.droppedPin(a, n1), .droppedPin(b, n2)):
            return a.latitude == b.latitude && a.longitude == b.longitude && n1 == n2
        default: return false
        }
    }

    /// The map item to show details for, if any.
    var mapItem: MKMapItem? {
        switch self {
        case .mapItem(let item), .searchResult(let item): return item
        default: return nil
        }
    }

    var savedPlaceID: UUID? {
        if case .saved(let id) = self { return id }
        return nil
    }

    func coordinate(in places: [Place]) -> CLLocationCoordinate2D? {
        switch self {
        case .saved(let id): return places.first { $0.id == id }?.coordinate
        case .mapItem(let item), .searchResult(let item): return item.location.coordinate
        case .droppedPin(let coordinate, _): return coordinate
        }
    }

    /// Identity used to reset the details view when the selection changes
    /// (a dropped pin keeps its identity while its name resolves).
    var identity: String {
        switch self {
        case .saved(let id): return "saved-\(id.uuidString)"
        case .mapItem(let item): return "item-\(ObjectIdentifier(item).hashValue)"
        case .searchResult(let item): return "search-\(ObjectIdentifier(item).hashValue)"
        case .droppedPin(let c, _): return "pin-\(c.latitude),\(c.longitude)"
        }
    }
}

/// State and behavior of the map screen (map, bottom sheet / sidebar, place
/// details), kept out of the view so it can be tested.
@MainActor
@Observable
final class MapModel {
    var selection: Selection?
    var cameraCommand: CameraCommand?
    var visibleRegion: MKCoordinateRegion?

    /// Side-by-side layout (sidebar + map) used in landscape and on wide
    /// windows such as the unfolded iPhone Duo.
    private(set) var isSplit = false
    /// The permanent bottom sheet (stacked layout only).
    var isMainSheetPresented = true
    /// The place details sheet (stacked layout only; the split layout shows
    /// details in the sidebar).
    var isDetailsSheetPresented = false
    var sheetDetent: PresentationDetent = .medium

    var overlayVisible = false
    var overlayTimeframe: RainfallTimeframe = .threeDays
    var overlayOpacity: Double = 0.3

    private(set) var didInitialFit = false

    /// Fixed height (not a fraction) so the collapsed header isn't clipped on
    /// short screens like the folded iPhone Duo.
    static let collapsedDetent = PresentationDetent.height(84)

    static func prefersSplit(for size: CGSize) -> Bool {
        size.width > size.height && size.width >= 560
    }

    /// How far below center a focused coordinate sits so the bottom sheet
    /// doesn't cover it. Zero in the split layout.
    var sheetBias: Double { isSplit ? 0 : 0.3 }

    // MARK: - Derived values for the map

    var droppedPin: (coordinate: CLLocationCoordinate2D, name: String?)? {
        if case .droppedPin(let coordinate, let name) = selection { return (coordinate, name) }
        return nil
    }

    var searchResult: MKMapItem? {
        if case .searchResult(let item) = selection { return item }
        return nil
    }

    func annotationSelection(in places: [Place]) -> AnnotationSelection? {
        switch selection {
        case .saved(let id): return places.first { $0.id == id }.map { .place($0) }
        case .droppedPin: return .newPin
        case .searchResult(let item): return .searchResult(item)
        case .mapItem, nil: return nil
        }
    }

    // MARK: - Selection

    /// Shows details for `selection` and moves the camera to it.
    func select(_ selection: Selection, places: [Place], focus: Bool = true) {
        self.selection = selection
        if !isSplit { isDetailsSheetPresented = true }
        if focus, let coordinate = selection.coordinate(in: places) {
            self.focus(on: coordinate)
        }
    }

    func closeDetails() {
        selection = nil
        isDetailsSheetPresented = false
        sheetDetent = .medium
    }

    /// A dropped pin's name finished reverse geocoding.
    func droppedPinNamed(_ name: String) {
        guard case .droppedPin(let coordinate, _) = selection else { return }
        selection = .droppedPin(coordinate, name: name)
    }

    /// A dropped pin was saved: show it as the saved place.
    func didSave(_ place: Place) {
        guard case .droppedPin = selection else { return }
        selection = .saved(place.id)
    }

    /// A saved place was removed while its details were open: keep a pin
    /// there so it doesn't vanish.
    func didUnsave(_ place: Place) {
        guard case .saved = selection else { return }
        selection = .droppedPin(place.coordinate, name: place.name)
    }

    // MARK: - Layout

    func applyLayout(split: Bool, places: [Place], animated: Bool) {
        guard split != isSplit || isMainSheetPresented == split else { return }
        isSplit = split
        isMainSheetPresented = !split
        if split {
            isDetailsSheetPresented = false
        } else if selection != nil {
            // Present the details sheet once the bottom sheet is back.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if self.selection != nil && !self.isSplit { self.isDetailsSheetPresented = true }
            }
        }
        if animated, let coordinate = selection?.coordinate(in: places) {
            // Re-center the selection for the new layout once the map resizes.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                self.focus(on: coordinate)
            }
        }
    }

    // MARK: - Camera

    func fitPlacesIfNeeded(_ places: [Place]) {
        guard !didInitialFit, !places.isEmpty else { return }
        didInitialFit = true
        cameraCommand = CameraCommand(action: .fitAllPlaces(places, bias: sheetBias))
    }

    func userLocationAvailable(_ coordinate: CLLocationCoordinate2D, hasPlaces: Bool) {
        guard !hasPlaces, !didInitialFit else { return }
        focus(on: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))
    }

    func centerOnUser() {
        cameraCommand = CameraCommand(action: .centerOnUser)
        if !isSplit { sheetDetent = Self.collapsedDetent }
    }

    /// Moves the camera to a coordinate, keeping it clear of the bottom sheet.
    func focus(on coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil) {
        let span = span ?? visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let center = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * sheetBias,
            longitude: coordinate.longitude
        )
        cameraCommand = CameraCommand(action: .setRegion(MKCoordinateRegion(center: center, span: span)))
    }
}
