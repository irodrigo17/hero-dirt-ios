import Combine
import MapKit
import UIKit

final class MapViewController: UIViewController {

    // MARK: - Dependencies

    private let placeStore: PlaceStore
    private let gridService = RainfallGridService()

    // MARK: - Map

    private let mapView = MKMapView()
    private static let placeAnnotationReuseID = "PlaceAnnotation"

    // MARK: - Overlay

    private var rainfallOverlay: RainfallMapOverlay?
    private var rainfallRenderer: RainfallOverlayRenderer?

    // MARK: - Annotations

    private var placeAnnotations: [UUID: MKPointAnnotation] = [:]
    private var hasInitiallyZoomed = false
    private var newPinAnnotation: MKPointAnnotation?
    private var searchResultAnnotation: MKPointAnnotation?
    private var selectedSearchResult: MKMapItem?
    private var resolvedAnnotationCategories: [MKPointAnnotation: MKPointOfInterestCategory] = [:]

    // MARK: - UI

    private let overlayControlsView = RainfallOverlayControlsView()
    private let locationButton = UIButton(type: .system)
    private weak var sheetVC: SheetViewController?
    private var selectionTask: Task<Void, Never>?
    private var categoryTask: Task<Void, Never>?

    // MARK: - State

    private var overlayVisible = false {
        didSet { updateRainfallOverlayVisibility() }
    }
    private var overlayTimeframe: RainfallTimeframe = .threeDays {
        didSet { refreshOverlayImage() }
    }
    private var overlayOpacity: Double = 0.3 {
        didSet { rainfallRenderer?.overlayOpacity = overlayOpacity; mapView.setNeedsDisplay() }
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(placeStore: PlaceStore) {
        self.placeStore = placeStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        setupOverlayControls()
        setupLocationButton()
        setupGestures()
        observeStores()
    }

    private var sheetPresented = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !sheetPresented {
            sheetPresented = true
            presentBottomSheet()
        }
        if placeStore.places.isEmpty {
            mapView.setUserTrackingMode(.follow, animated: true)
        }
    }

    // MARK: - Map setup

    private func setupMap() {
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.selectableMapFeatures = [.pointsOfInterest]
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .adaptive
        compass.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(compass)

        let scale = MKScaleView(mapView: mapView)
        scale.scaleVisibility = .adaptive
        scale.legendAlignment = .leading
        scale.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scale)

        NSLayoutConstraint.activate([
            compass.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            compass.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            scale.topAnchor.constraint(equalTo: compass.bottomAnchor, constant: 8),
            scale.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
        ])

        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.placeAnnotationReuseID
        )
    }

    // MARK: - Overlay controls

    private func setupOverlayControls() {
        overlayControlsView.onVisibilityChanged = { [weak self] visible in
            self?.overlayVisible = visible
            if visible { self?.gridService.refetch() }
        }
        overlayControlsView.onTimeframeChanged = { [weak self] tf in
            self?.overlayTimeframe = tf
        }
        overlayControlsView.onOpacityChanged = { [weak self] opacity in
            self?.overlayOpacity = opacity
        }

        overlayControlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayControlsView)
        NSLayoutConstraint.activate([
            overlayControlsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            overlayControlsView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
        ])
    }

    private func setupLocationButton() {
        locationButton.setImage(UIImage(systemName: "location.fill"), for: .normal)
        locationButton.tintColor = .label
        locationButton.accessibilityLabel = "Center map on your location"
        locationButton.addTarget(self, action: #selector(centerOnUser), for: .touchUpInside)

        let bg = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        bg.layer.cornerRadius = .cornerSmall
        bg.clipsToBounds = true
        bg.isUserInteractionEnabled = false
        bg.translatesAutoresizingMaskIntoConstraints = false
        locationButton.insertSubview(bg, at: 0)

        locationButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(locationButton)
        NSLayoutConstraint.activate([
            locationButton.topAnchor.constraint(equalTo: overlayControlsView.bottomAnchor, constant: 10),
            locationButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            locationButton.widthAnchor.constraint(equalToConstant: 44),
            locationButton.heightAnchor.constraint(equalToConstant: 44),
            bg.topAnchor.constraint(equalTo: locationButton.topAnchor),
            bg.bottomAnchor.constraint(equalTo: locationButton.bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: locationButton.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: locationButton.trailingAnchor),
        ])
    }

    // MARK: - Gestures

    private func setupGestures() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)
    }

    // MARK: - Store observation

    private func observeStores() {
        placeStore.$places
            .receive(on: DispatchQueue.main)
            .sink { [weak self] places in self?.syncAnnotations(for: places) }
            .store(in: &cancellables)

        gridService.$gridVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOverlayImage() }
            .store(in: &cancellables)

        gridService.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in self?.overlayControlsView.isLoading = loading }
            .store(in: &cancellables)
    }

    // MARK: - Bottom sheet

    private func presentBottomSheet() {
        let sheet = SheetViewController(placeStore: placeStore)
        sheet.delegate = self
        sheet.modalPresentationStyle = .pageSheet
        sheet.isModalInPresentation = true

        let collapsedIdentifier = UISheetPresentationController.Detent.Identifier("collapsed")
        if let sp = sheet.sheetPresentationController {
            sp.detents = [
                .custom(identifier: collapsedIdentifier) { context in
                    context.maximumDetentValue * 0.09
                },
                .medium(),
                .large(),
            ]
            sp.selectedDetentIdentifier = .medium
            sp.largestUndimmedDetentIdentifier = .large
            sp.prefersScrollingExpandsWhenScrolledToEdge = false
            sp.prefersEdgeAttachedInCompactHeight = true
            sp.prefersGrabberVisible = true
        }

        present(sheet, animated: false)
        sheetVC = sheet
    }

    private func showPlaceDetails(coordinate: CLLocationCoordinate2D, placeID: UUID?, mapItem: MKMapItem?) {
        let detailsVC = PlaceDetailsViewController(
            coordinate: coordinate,
            placeID: placeID,
            mapItem: mapItem,
            placeStore: placeStore
        )
        detailsVC.onDismiss = { [weak self] in
            self?.clearSelection()
        }
        let navVC = UINavigationController(rootViewController: detailsVC)
        if let sp = navVC.sheetPresentationController {
            sp.detents = [.medium(), .large()]
            sp.largestUndimmedDetentIdentifier = .large
            sp.prefersGrabberVisible = true
        }
        sheetVC?.present(navVC, animated: true)
    }

    // MARK: - Annotation sync

    private func syncAnnotations(for places: [Place]) {
        let currentIDs = Set(placeAnnotations.keys)
        let newIDs = Set(places.map(\.id))

        let toRemove = currentIDs.subtracting(newIDs)
        let toAdd = newIDs.subtracting(currentIDs)

        for id in toRemove {
            if let ann = placeAnnotations.removeValue(forKey: id) {
                mapView.removeAnnotation(ann)
            }
        }
        for place in places where toAdd.contains(place.id) {
            let ann = MKPointAnnotation()
            ann.coordinate = place.coordinate
            ann.title = place.name
            placeAnnotations[place.id] = ann
            mapView.addAnnotation(ann)
        }

        categoryTask?.cancel()
        categoryTask = Task { await fetchCategories(for: places) }

        if !hasInitiallyZoomed {
            hasInitiallyZoomed = true
            if !placeAnnotations.isEmpty {
                mapView.showAnnotations(Array(placeAnnotations.values), animated: false)
            }
        }
    }

    @MainActor
    private func fetchCategories(for places: [Place]) async {
        await withTaskGroup(of: (UUID, MKPointOfInterestCategory?).self) { group in
            for place in places {
                guard let mapItemId = place.mapItemId else { continue }
                group.addTask {
                    let item = try? await MKMapItemRequest(mapItemIdentifier: mapItemId).mapItem
                    return (place.id, item?.pointOfInterestCategory)
                }
            }
            for await (id, category) in group {
                guard !Task.isCancelled, let ann = placeAnnotations[id] else { continue }
                if let category {
                    resolvedAnnotationCategories[ann] = category
                    if let view = mapView.view(for: ann) as? MKMarkerAnnotationView {
                        view.markerTintColor = category.iconColor
                        view.glyphImage = UIImage(systemName: category.sfSymbol)
                    }
                }
            }
        }
    }

    // MARK: - Rainfall overlay

    private func updateRainfallOverlayVisibility() {
        overlayControlsView.isOverlayVisible = overlayVisible
        if overlayVisible {
            if rainfallOverlay == nil, let bounds = gridService.gridBounds {
                addOverlay(for: bounds)
            }
            refreshOverlayImage()
            gridService.refetch()
        } else {
            if let overlay = rainfallOverlay {
                mapView.removeOverlay(overlay)
                rainfallOverlay = nil
                rainfallRenderer = nil
            }
        }
    }

    private func addOverlay(for bounds: RainfallGridBounds) {
        let overlay = RainfallMapOverlay(bounds: bounds)
        rainfallOverlay = overlay
        mapView.addOverlay(overlay, level: .aboveRoads)
    }

    private func refreshOverlayImage() {
        guard overlayVisible else { return }

        if let bounds = gridService.gridBounds {
            if rainfallOverlay == nil {
                addOverlay(for: bounds)
            } else if let existing = rainfallOverlay,
                !MKMapRectEqualToRect(existing.boundingMapRect, RainfallMapOverlay(bounds: bounds).boundingMapRect)
            {
                mapView.removeOverlay(existing)
                addOverlay(for: bounds)
            }
        }

        rainfallRenderer?.image = gridService.rainfallImage(for: overlayTimeframe)
        mapView.setNeedsDisplay()
    }

    // MARK: - Selection

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        let point = gr.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        placeNewPin(at: coordinate)
    }

    private func placeNewPin(at coordinate: CLLocationCoordinate2D) {
        if let existing = newPinAnnotation {
            mapView.removeAnnotation(existing)
        }
        clearSearchResult()

        let ann = MKPointAnnotation()
        ann.coordinate = coordinate
        ann.title = "New place"
        newPinAnnotation = ann
        mapView.addAnnotation(ann)
        mapView.selectAnnotation(ann, animated: true)
        centerAboveSheet(coordinate)
    }

    private func clearSelection() {
        if let ann = newPinAnnotation {
            mapView.removeAnnotation(ann)
            newPinAnnotation = nil
        }
        clearSearchResult()
        mapView.deselectAnnotation(mapView.selectedAnnotations.first, animated: true)
    }

    private func clearSearchResult() {
        if let ann = searchResultAnnotation {
            mapView.removeAnnotation(ann)
            searchResultAnnotation = nil
        }
        selectedSearchResult = nil
    }

    // MARK: - Helpers

    @objc private func centerOnUser() {
        mapView.setUserTrackingMode(.follow, animated: true)
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func centerAboveSheet(_ coordinate: CLLocationCoordinate2D) {
        let span = mapView.region.span
        let newCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.25,
            longitude: coordinate.longitude
        )
        let region = MKCoordinateRegion(center: newCenter, span: span)
        mapView.setRegion(region, animated: true)
    }
}

// MARK: - MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation),
              !(annotation is MKMapFeatureAnnotation) else { return nil }

        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: Self.placeAnnotationReuseID,
            for: annotation
        ) as! MKMarkerAnnotationView

        if annotation === newPinAnnotation {
            view.markerTintColor = .systemBlue
            view.glyphImage = UIImage(systemName: "mappin")
            view.titleVisibility = .visible
        } else if annotation === searchResultAnnotation, let item = selectedSearchResult {
            let category = item.pointOfInterestCategory
            view.markerTintColor = category?.iconColor ?? .systemOrange
            view.glyphImage = UIImage(systemName: category?.sfSymbol ?? "mappin")
        } else {
            // Saved place annotation
            let category = resolvedAnnotationCategories[annotation as! MKPointAnnotation]
            view.markerTintColor = category?.iconColor ?? .systemOrange
            view.glyphImage = UIImage(systemName: category?.sfSymbol ?? "mappin")
        }
        view.canShowCallout = false
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        guard !(annotation is MKUserLocation) else { return }
        selectionTask?.cancel()
        selectionTask = Task { @MainActor in
            if let feature = annotation as? MKMapFeatureAnnotation {
                guard let item = try? await MKMapItemRequest(mapFeatureAnnotation: feature).mapItem else { return }
                guard !Task.isCancelled else { return }
                showPlaceDetails(coordinate: item.location.coordinate, placeID: nil, mapItem: item)
                centerAboveSheet(item.location.coordinate)
            } else if let placeAnn = annotation as? MKPointAnnotation {
                guard !Task.isCancelled else { return }
                if placeAnn === newPinAnnotation {
                    showPlaceDetails(coordinate: placeAnn.coordinate, placeID: nil, mapItem: nil)
                } else if placeAnn === searchResultAnnotation, let item = selectedSearchResult {
                    showPlaceDetails(coordinate: item.location.coordinate, placeID: nil, mapItem: item)
                } else if let placeID = placeAnnotations.first(where: { $0.value === placeAnn })?.key {
                    showPlaceDetails(coordinate: placeAnn.coordinate, placeID: placeID, mapItem: nil)
                }
            }
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        sheetVC?.visibleRegion = mapView.region
        if overlayVisible {
            gridService.updateRegion(mapView.region)
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        if let rainfallOverlay = overlay as? RainfallMapOverlay {
            let renderer = RainfallOverlayRenderer(overlay: rainfallOverlay)
            renderer.image = gridService.rainfallImage(for: overlayTimeframe)
            renderer.overlayOpacity = overlayOpacity
            rainfallRenderer = renderer
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - SheetViewControllerDelegate

extension MapViewController: SheetViewControllerDelegate {

    func sheet(_ vc: SheetViewController, didSelectPlace place: Place) {
        clearSearchResult()
        if let existing = newPinAnnotation {
            mapView.removeAnnotation(existing)
            newPinAnnotation = nil
        }
        if let ann = placeAnnotations[place.id] {
            mapView.selectAnnotation(ann, animated: false)
            centerAboveSheet(place.coordinate)
        }
        showPlaceDetails(coordinate: place.coordinate, placeID: place.id, mapItem: nil)
    }

    func sheet(_ vc: SheetViewController, didSelectSearchResult item: MKMapItem) {
        if let existing = newPinAnnotation {
            mapView.removeAnnotation(existing)
            newPinAnnotation = nil
        }
        clearSearchResult()

        selectedSearchResult = item
        let ann = MKPointAnnotation()
        ann.coordinate = item.location.coordinate
        ann.title = item.name
        searchResultAnnotation = ann
        mapView.addAnnotation(ann)
        mapView.selectAnnotation(ann, animated: false)
        centerAboveSheet(item.location.coordinate)
        showPlaceDetails(coordinate: item.location.coordinate, placeID: nil, mapItem: item)
    }
}
