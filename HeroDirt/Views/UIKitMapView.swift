import MapKit
import SwiftUI

// MARK: - Camera Command

struct CameraCommand {
    enum Action {
        case centerOnUser
        case setRegion(MKCoordinateRegion)
        /// `bias` shifts the framed region up by that fraction so it clears
        /// the bottom sheet (0 when there is no sheet).
        case fitAllPlaces([Place], bias: Double)
    }
    let id = UUID()
    let action: Action
}

// MARK: - Annotation Selection

enum AnnotationSelection {
    case place(Place)
    case newPin
    case searchResult(MKMapItem)
}

// MARK: - Annotations

private final class PlaceAnnotation: NSObject, MKAnnotation {
    var place: Place
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?

    init(place: Place) {
        self.place = place
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
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
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
    let newPinCoordinate: CLLocationCoordinate2D?
    let newPinTitle: String?
    let selectedSearchResult: MKMapItem?
    let selectedAnnotation: AnnotationSelection?

    let overlayVisible: Bool
    let overlayImage: UIImage?
    let overlayBounds: RainfallGridBounds?
    let overlayOpacity: Double

    @Binding var cameraCommand: CameraCommand?

    var onRegionChanged: (MKCoordinateRegion) -> Void = { _ in }
    var onRegionWillChange: () -> Void = {}
    var onLongPress: (CLLocationCoordinate2D) -> Void = { _ in }
    var onAnnotationSelected: (AnnotationSelection) -> Void = { _ in }
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
        c.updateAnnotations(on: mapView, view: self)
        c.updateSelection(on: mapView, selectedAnnotation: selectedAnnotation)
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
            onAnnotationSelected: (AnnotationSelection) -> Void,
            onFeatureTapped: (MKMapItem) -> Void,
            onTap: () -> Void,
            onUserLocationAvailable: (CLLocationCoordinate2D) -> Void
        )

        var callbacks: Callbacks = ({ _ in }, {}, { _ in }, { _ in }, { _ in }, {}, { _ in })
        private var didFireInitialUserLocation = false
        var lastCommandID: UUID?

        fileprivate let rainfallOverlay = RainfallImageOverlay()
        private weak var rainfallRenderer: RainfallImageRenderer?

        // MARK: - Annotation management

        /// Annotations currently animating out; ignored when diffing.
        private var removing = Set<ObjectIdentifier>()

        func updateAnnotations(on mapView: MKMapView, view: UIKitMapView) {
            let existing = mapView.annotations.filter {
                !($0 is MKUserLocation) && !($0 is MKMapFeatureAnnotation)
                    && !removing.contains(ObjectIdentifier($0))
            }

            var desired: [(id: String, make: () -> MKAnnotation)] = []
            for place in view.places {
                desired.append((place.id.uuidString, { PlaceAnnotation(place: place) }))
            }
            if let coord = view.newPinCoordinate {
                desired.append(("new-place", { NewPinAnnotation(coordinate: coord) }))
            }
            if let item = view.selectedSearchResult {
                let tag = item.identifier?.rawValue ?? "search-result"
                desired.append((tag, { SearchResultAnnotation(mapItem: item) }))
            }
            let desiredIDs = Set(desired.map(\.id))

            var existingIDs = Set<String>()
            var toRemove: [MKAnnotation] = []
            for annotation in existing {
                guard let id = annotationID(annotation), desiredIDs.contains(id),
                      existingIDs.insert(id).inserted
                else {
                    toRemove.append(annotation)
                    continue
                }
            }

            // Animate removals: shrink and fade, then remove.
            for annotation in toRemove {
                guard let annotationView = mapView.view(for: annotation) else {
                    mapView.removeAnnotation(annotation)
                    continue
                }
                let key = ObjectIdentifier(annotation)
                removing.insert(key)
                UIView.animate(
                    withDuration: 0.22,
                    delay: 0,
                    options: [.curveEaseIn, .beginFromCurrentState],
                    animations: {
                        annotationView.alpha = 0
                        annotationView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                    },
                    completion: { [weak self, weak mapView] _ in
                        mapView?.removeAnnotation(annotation)
                        annotationView.alpha = 1
                        annotationView.transform = .identity
                        self?.removing.remove(key)
                    }
                )
            }

            // Additions pop in via MKMarkerAnnotationView.animatesWhenAdded.
            let toAdd = desired.filter { !existingIDs.contains($0.id) }.map { $0.make() }
            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
            }

            // Update annotations that stayed.
            for annotation in existing {
                if let pin = annotation as? NewPinAnnotation, let coord = view.newPinCoordinate {
                    if pin.coordinate.latitude != coord.latitude
                        || pin.coordinate.longitude != coord.longitude
                    {
                        pin.coordinate = coord
                    }
                    if let title = view.newPinTitle, pin.title != title {
                        pin.title = title
                    }
                }
                guard let ann = annotation as? PlaceAnnotation else { continue }
                if let place = view.places.first(where: { $0.id == ann.place.id }),
                   ann.place.name != place.name
                {
                    ann.place = place
                    ann.title = place.name
                }
                if let annView = mapView.view(for: ann) as? MKMarkerAnnotationView {
                    let category = ann.place.mapItem?.pointOfInterestCategory
                    annView.markerTintColor = UIColor(category?.iconColor ?? .orange)
                    annView.glyphImage = UIImage(systemName: category?.sfSymbol ?? "mappin")
                }
            }
        }

        private func annotationID(_ annotation: MKAnnotation) -> String? {
            if let a = annotation as? PlaceAnnotation { return a.place.id.uuidString }
            if annotation is NewPinAnnotation { return "new-place" }
            if let a = annotation as? SearchResultAnnotation {
                return a.mapItem.identifier?.rawValue ?? "search-result"
            }
            return nil
        }

        func updateSelection(on mapView: MKMapView, selectedAnnotation: AnnotationSelection?) {
            guard let selection = selectedAnnotation else {
                mapView.selectedAnnotations
                    .filter { !($0 is MKUserLocation) && !($0 is MKMapFeatureAnnotation) }
                    .forEach { mapView.deselectAnnotation($0, animated: true) }
                return
            }
            if let current = mapView.selectedAnnotations.first, matches(current, selection) { return }
            if let target = mapView.annotations.first(where: { matches($0, selection) }) {
                mapView.selectAnnotation(target, animated: true)
            }
        }

        private func matches(_ annotation: MKAnnotation, _ selection: AnnotationSelection) -> Bool {
            switch selection {
            case .place(let place):
                return (annotation as? PlaceAnnotation)?.place.id == place.id
            case .newPin:
                return annotation is NewPinAnnotation
            case .searchResult(let item):
                return (annotation as? SearchResultAnnotation)?.mapItem.identifier == item.identifier
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
            case .fitAllPlaces(let places, let bias):
                fitAllPlaces(places, bias: bias, on: mapView)
            }
        }

        private func fitAllPlaces(_ places: [Place], bias: Double, on mapView: MKMapView) {
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
            // With a bottom sheet (bias > 0) the places need to sit in the top
            // part of the map, so zoom out more and shift the center down.
            let zoom = bias > 0 ? 1.6 : 1.3
            let regionCenter = CLLocationCoordinate2D(
                latitude: centerLat - latSpan * bias * 2.33,
                longitude: centerLon
            )
            let region = MKCoordinateRegion(
                center: regionCenter,
                span: MKCoordinateSpan(latitudeDelta: latSpan * zoom, longitudeDelta: lonSpan * zoom)
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
                let category = ann.place.mapItem?.pointOfInterestCategory
                view.markerTintColor = UIColor(category?.iconColor ?? .orange)
                view.glyphImage = UIImage(systemName: category?.sfSymbol ?? "mappin")
                view.canShowCallout = false
                view.animatesWhenAdded = true
                view.displayPriority = .required
                return view
            }

            if annotation is NewPinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: "new-pin", for: annotation
                ) as! MKMarkerAnnotationView
                view.markerTintColor = .systemBlue
                view.glyphImage = nil
                view.canShowCallout = false
                view.animatesWhenAdded = true
                view.displayPriority = .required
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
                view.animatesWhenAdded = true
                view.displayPriority = .required
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let ann = annotation as? PlaceAnnotation {
                callbacks.onAnnotationSelected(.place(ann.place))
            } else if annotation is NewPinAnnotation {
                callbacks.onAnnotationSelected(.newPin)
            } else if let ann = annotation as? SearchResultAnnotation {
                callbacks.onAnnotationSelected(.searchResult(ann.mapItem))
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
