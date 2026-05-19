import MapKit
import SwiftUI

// MARK: - Camera Command

struct CameraCommand {
    enum Action {
        case centerOnUser
        case setRegion(MKCoordinateRegion)
        case fitAllPlaces([Place])
    }
    let id = UUID()
    let action: Action
}

// MARK: - Annotations

private final class PlaceAnnotation: NSObject, MKAnnotation {
    let placeID: UUID
    let tag: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?

    init(place: Place) {
        self.placeID = place.id
        self.tag = place.id.uuidString
        self.coordinate = place.coordinate
        self.title = place.name
    }
}

private final class NewPinAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String? = "New place"

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

private final class SearchResultAnnotation: NSObject, MKAnnotation {
    let mapItem: MKMapItem
    let tag: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
        self.tag = mapItem.identifier?.rawValue ?? "search-result"
        self.coordinate = mapItem.location.coordinate
        self.title = mapItem.name
    }
}

// MARK: - Rainfall Overlay

private final class RainfallImageOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D = .init()
    var boundingMapRect: MKMapRect = .world
}

private final class RainfallImageRenderer: MKOverlayRenderer {
    var image: UIImage?
    var opacity: Double = 0.3
    var overlayBounds: RainfallGridBounds?

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let image, let cgImage = image.cgImage, let bounds = overlayBounds else { return }

        let tl = MKMapPoint(bounds.topLeft)
        let br = MKMapPoint(bounds.bottomRight)
        let boundsRect = MKMapRect(
            origin: MKMapPoint(x: min(tl.x, br.x), y: min(tl.y, br.y)),
            size: MKMapSize(width: abs(br.x - tl.x), height: abs(br.y - tl.y))
        )
        let drawRect = rect(for: boundsRect)

        context.saveGState()
        context.setAlpha(CGFloat(opacity))
        context.translateBy(x: drawRect.minX, y: drawRect.minY + drawRect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: drawRect.size))
        context.restoreGState()
    }
}

// MARK: - UIViewRepresentable

struct UIKitMapView: UIViewRepresentable {
    let places: [Place]
    let resolvedCategories: [UUID: MKPointOfInterestCategory]
    let newPinCoordinate: CLLocationCoordinate2D?
    let newPinTitle: String?
    let selectedSearchResult: MKMapItem?
    let selectedTag: String?

    let overlayVisible: Bool
    let overlayImage: UIImage?
    let overlayBounds: RainfallGridBounds?
    let overlayOpacity: Double

    @Binding var cameraCommand: CameraCommand?

    var onRegionChanged: (MKCoordinateRegion) -> Void = { _ in }
    var onRegionWillChange: () -> Void = {}
    var onLongPress: (CLLocationCoordinate2D) -> Void = { _ in }
    var onAnnotationSelected: (String) -> Void = { _ in }
    var onFeatureTapped: (MKMapItem) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onUserLocationAvailable: (CLLocationCoordinate2D) -> Void = { _ in }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.selectableMapFeatures = [.pointsOfInterest]
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "place")
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "new-pin")
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "search-result")

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        mapView.addOverlay(context.coordinator.rainfallOverlay, level: .aboveRoads)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let c = context.coordinator
        c.callbacks = (onRegionChanged, onRegionWillChange, onLongPress, onAnnotationSelected, onFeatureTapped, onTap, onUserLocationAvailable)
        c.resolvedCategories = resolvedCategories

        c.updateAnnotations(on: mapView, view: self)
        c.updateSelection(on: mapView, selectedTag: selectedTag)
        c.updateRainfallOverlay(
            image: overlayVisible ? overlayImage : nil,
            bounds: overlayBounds,
            opacity: overlayOpacity
        )

        if let command = cameraCommand, command.id != c.lastCommandID {
            c.lastCommandID = command.id
            c.execute(command: command, on: mapView)
            DispatchQueue.main.async { cameraCommand = nil }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        typealias Callbacks = (
            onRegionChanged: (MKCoordinateRegion) -> Void,
            onRegionWillChange: () -> Void,
            onLongPress: (CLLocationCoordinate2D) -> Void,
            onAnnotationSelected: (String) -> Void,
            onFeatureTapped: (MKMapItem) -> Void,
            onTap: () -> Void,
            onUserLocationAvailable: (CLLocationCoordinate2D) -> Void
        )

        var callbacks: Callbacks = ({ _ in }, {}, { _ in }, { _ in }, { _ in }, {}, { _ in })
        private var didFireInitialUserLocation = false
        var resolvedCategories: [UUID: MKPointOfInterestCategory] = [:]
        var lastCommandID: UUID?

        fileprivate let rainfallOverlay = RainfallImageOverlay()
        private weak var rainfallRenderer: RainfallImageRenderer?

        // MARK: - Annotation management

        func updateAnnotations(on mapView: MKMapView, view: UIKitMapView) {
            let existing = mapView.annotations.filter {
                !($0 is MKUserLocation) && !($0 is MKMapFeatureAnnotation)
            }

            let existingIDs = Set(existing.compactMap { annotationID($0) })

            var desired: [(id: String, annotation: NSObject & MKAnnotation)] = []
            for place in view.places {
                desired.append((place.id.uuidString, PlaceAnnotation(place: place)))
            }
            if let coord = view.newPinCoordinate {
                desired.append(("new-place", NewPinAnnotation(coordinate: coord)))
            }
            if let item = view.selectedSearchResult {
                let tag = item.identifier?.rawValue ?? "search-result"
                desired.append((tag, SearchResultAnnotation(mapItem: item)))
            }

            let desiredIDs = Set(desired.map(\.id))

            if existingIDs == desiredIDs {
                // Update new-pin coordinate if it moved
                if let existingPin = existing.first(where: { $0 is NewPinAnnotation }) as? NewPinAnnotation,
                   let coord = view.newPinCoordinate
                {
                    if existingPin.coordinate.latitude != coord.latitude
                        || existingPin.coordinate.longitude != coord.longitude
                    {
                        existingPin.coordinate = coord
                    }
                    if let title = view.newPinTitle, existingPin.title != title {
                        existingPin.title = title
                    }
                }
                // Update title and marker appearance if changed
                for annotation in existing {
                    guard let ann = annotation as? PlaceAnnotation else { continue }
                    if let place = view.places.first(where: { $0.id == ann.placeID }),
                       ann.title != place.name
                    {
                        ann.title = place.name
                    }
                    if let annView = mapView.view(for: ann) as? MKMarkerAnnotationView {
                        let category = resolvedCategories[ann.placeID]
                        annView.markerTintColor = UIColor(category?.iconColor ?? .orange)
                        annView.glyphImage = UIImage(systemName: category?.sfSymbol ?? "mappin")
                    }
                }
                return
            }

            mapView.removeAnnotations(existing)
            mapView.addAnnotations(desired.map(\.annotation))
        }

        private func annotationID(_ annotation: MKAnnotation) -> String? {
            if let a = annotation as? PlaceAnnotation { return a.tag }
            if annotation is NewPinAnnotation { return "new-place" }
            if let a = annotation as? SearchResultAnnotation { return a.tag }
            return nil
        }

        func updateSelection(on mapView: MKMapView, selectedTag: String?) {
            guard let tag = selectedTag else {
                mapView.selectedAnnotations
                    .filter { !($0 is MKUserLocation) && !($0 is MKMapFeatureAnnotation) }
                    .forEach { mapView.deselectAnnotation($0, animated: true) }
                return
            }
            if let current = mapView.selectedAnnotations.first,
               annotationID(current) == tag { return }
            if let target = mapView.annotations.first(where: { annotationID($0) == tag }) {
                mapView.selectAnnotation(target, animated: true)
            }
        }

        func updateRainfallOverlay(image: UIImage?, bounds: RainfallGridBounds?, opacity: Double) {
            guard let renderer = rainfallRenderer else { return }
            let changed = renderer.image !== image
                || renderer.overlayBounds != bounds
                || renderer.opacity != opacity
            if changed {
                renderer.image = image
                renderer.overlayBounds = bounds
                renderer.opacity = opacity
                renderer.setNeedsDisplay()
            }
        }

        func execute(command: CameraCommand, on mapView: MKMapView) {
            switch command.action {
            case .centerOnUser:
                if let coordinate = mapView.userLocation.location?.coordinate {
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
                    )
                    mapView.setRegion(region, animated: true)
                }
            case .setRegion(let region):
                mapView.setRegion(region, animated: true)
            case .fitAllPlaces(let places):
                fitAllPlaces(places, on: mapView)
            }
        }

        private func fitAllPlaces(_ places: [Place], on mapView: MKMapView) {
            guard !places.isEmpty else {
                if let coordinate = mapView.userLocation.location?.coordinate {
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
                    )
                    mapView.setRegion(region, animated: true)
                }
                return
            }
            var minLat = places[0].coordinate.latitude
            var maxLat = minLat
            var minLon = places[0].coordinate.longitude
            var maxLon = minLon
            for place in places {
                minLat = min(minLat, place.coordinate.latitude)
                maxLat = max(maxLat, place.coordinate.latitude)
                minLon = min(minLon, place.coordinate.longitude)
                maxLon = max(maxLon, place.coordinate.longitude)
            }
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            let minSpan = 0.2
            let latSpan = max(maxLat - minLat, minSpan)
            let lonSpan = max(maxLon - minLon, minSpan)
            let regionCenter = CLLocationCoordinate2D(
                latitude: centerLat - latSpan * 0.7,
                longitude: centerLon
            )
            let region = MKCoordinateRegion(
                center: regionCenter,
                span: MKCoordinateSpan(latitudeDelta: latSpan * 1.6, longitudeDelta: lonSpan * 1.6)
            )
            mapView.setRegion(region, animated: true)
        }

        // MARK: - Gesture handlers

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            callbacks.onLongPress(coordinate)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            callbacks.onTap()
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let ann = annotation as? PlaceAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: "place", for: ann
                ) as! MKMarkerAnnotationView
                let category = resolvedCategories[ann.placeID]
                view.markerTintColor = UIColor(category?.iconColor ?? .orange)
                view.glyphImage = UIImage(systemName: category?.sfSymbol ?? "mappin")
                view.canShowCallout = false
                return view
            }

            if annotation is NewPinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: "new-pin", for: annotation
                ) as! MKMarkerAnnotationView
                view.markerTintColor = .systemBlue
                view.glyphImage = nil
                view.canShowCallout = false
                return view
            }

            if let ann = annotation as? SearchResultAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: "search-result", for: ann
                ) as! MKMarkerAnnotationView
                let category = ann.mapItem.pointOfInterestCategory
                view.markerTintColor = UIColor(category?.iconColor ?? .orange)
                view.glyphImage = UIImage(systemName: category?.sfSymbol ?? "mappin")
                view.canShowCallout = false
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let ann = annotation as? PlaceAnnotation {
                callbacks.onAnnotationSelected(ann.tag)
            } else if annotation is NewPinAnnotation {
                callbacks.onAnnotationSelected("new-place")
            } else if let ann = annotation as? SearchResultAnnotation {
                callbacks.onAnnotationSelected(ann.tag)
            } else if let feature = annotation as? MKMapFeatureAnnotation {
                let mapItem = MKMapItem(
                    location: CLLocation(
                        latitude: feature.coordinate.latitude,
                        longitude: feature.coordinate.longitude
                    ),
                    address: nil
                )
                mapItem.name = feature.title
                callbacks.onFeatureTapped(mapItem)
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            callbacks.onRegionWillChange()
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didFireInitialUserLocation,
                  let location = userLocation.location,
                  location.horizontalAccuracy >= 0
            else { return }
            didFireInitialUserLocation = true
            callbacks.onUserLocationAvailable(location.coordinate)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            callbacks.onRegionChanged(mapView.region)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is RainfallImageOverlay {
                let renderer = RainfallImageRenderer(overlay: overlay)
                rainfallRenderer = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
