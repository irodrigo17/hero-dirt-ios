import MapKit
import SwiftUI

struct MapView: View {
    @EnvironmentObject private var placeStore: PlaceStore

    @State private var cameraCommand: CameraCommand?
    @State private var selectedTag: String?
    @State private var newPinCoordinate: CLLocationCoordinate2D?
    @State private var newPinName: String?
    @State private var sheetPresented = true
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showingPlaceDetails = false
    @State private var selectedPlace: Place?
    @State private var selectedMapItem: MKMapItem?
    @State private var selectedSearchResult: MKMapItem?

    @State private var resolvedCategories: [UUID: MKPointOfInterestCategory] = [:]

    @StateObject private var gridService = RainfallGridService()
    @State private var overlayVisible = false
    @State private var overlayTimeframe: RainfallTimeframe = .threeDays
    @State private var overlayOpacity: Double = 0.3
    @State private var visibleRegion: MKCoordinateRegion?

    private let collapsedDetent = PresentationDetent.fraction(0.09)

    var body: some View {
        UIKitMapView(
            places: placeStore.places,
            resolvedCategories: resolvedCategories,
            newPinCoordinate: newPinCoordinate,
            newPinTitle: newPinName,
            selectedSearchResult: selectedSearchResult,
            selectedTag: selectedTag,
            overlayVisible: overlayVisible,
            overlayImage: gridService.rainfallImage(for: overlayTimeframe),
            overlayBounds: gridService.gridBounds,
            overlayOpacity: overlayOpacity,
            cameraCommand: $cameraCommand,
            onRegionChanged: { region in
                visibleRegion = region
                if overlayVisible {
                    gridService.updateRegion(region)
                }
            },
            onRegionWillChange: {
                if overlayVisible {
                    gridService.cancelUpdate()
                }
            },
            onLongPress: { coordinate in
                newPinCoordinate = coordinate
                newPinName = nil
                selectedPlace = nil
                selectedMapItem = nil
                selectedSearchResult = nil
                selectedTag = "new-place"
                showingPlaceDetails = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            },
            onAnnotationSelected: handleAnnotationSelected,
            onFeatureTapped: { item in
                selectedMapItem = item
                selectedPlace = nil
                newPinCoordinate = nil
                selectedSearchResult = nil
                showingPlaceDetails = true
                centerAboveSheet(item.location.coordinate)
            },
            onTap: {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            },
            onUserLocationAvailable: { coordinate in
                guard placeStore.places.isEmpty else { return }
                centerAboveSheet(
                    coordinate,
                )
            }
        )
        .ignoresSafeArea()
        .onAppear {
            if !placeStore.places.isEmpty {
                cameraCommand = CameraCommand(action: .fitAllPlaces(placeStore.places))
            }
        }
        .task(id: placeStore.places.map(\.id)) {
            await fetchResolvedCategories()
        }
        .onChange(of: overlayVisible) { _, visible in
            if visible, let region = visibleRegion {
                gridService.timeframe = overlayTimeframe
                gridService.updateRegion(region)
            }
        }
        .onChange(of: overlayTimeframe) { _, timeframe in
            if overlayVisible {
                gridService.timeframe = timeframe
                gridService.refetch()
            }
        }
        .sheet(
            isPresented: $sheetPresented,
            onDismiss: {
                Task { @MainActor in sheetPresented = true }
            }
        ) {
            mainSheet
        }
    }

    // MARK: - Sheets

    private var mainSheet: some View {
        SheetView(
            onSelectPlace: { place in
                selectedPlace = place
                selectedMapItem = nil
                newPinCoordinate = nil
                selectedSearchResult = nil
                selectedTag = place.id.uuidString
                showingPlaceDetails = true
                centerAboveSheet(place.coordinate)
            },
            onSelectSearchResult: { item in
                selectedSearchResult = item
                selectedMapItem = item
                selectedPlace = nil
                newPinCoordinate = nil
                selectedTag = item.identifier?.rawValue ?? "search-result"
                showingPlaceDetails = true
                centerAboveSheet(item.location.coordinate)
            },
            onSearchFocusChanged: { focused in
                selectedDetent = focused ? .large : .medium
            },
            visibleRegion: visibleRegion,
            selectedDetent: selectedDetent,
            overlayVisible: $overlayVisible,
            overlayTimeframe: $overlayTimeframe,
            overlayOpacity: $overlayOpacity,
            isOverlayLoading: gridService.isLoading,
            onCenterLocation: {
                cameraCommand = CameraCommand(action: .centerOnUser)
                selectedDetent = collapsedDetent
            }
        )
        .presentationDetents(
            [collapsedDetent, .medium, .large],
            selection: $selectedDetent
        )
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(true)
        .sheet(
            isPresented: $showingPlaceDetails,
            onDismiss: {
                selectedTag = nil
                selectedPlace = nil
                newPinCoordinate = nil
                newPinName = nil
                selectedSearchResult = nil
                selectedMapItem = nil
                selectedDetent = .medium
            }
        ) {
            placeDetailsSheet
        }
    }

    private var placeDetailsSheet: some View {
        PlaceDetailsView(
            coordinate: selectedPlace?.coordinate
                ?? selectedMapItem?.location.coordinate
                ?? newPinCoordinate
                ?? CLLocationCoordinate2D(),
            placeID: selectedPlace?.id,
            mapItem: selectedMapItem,
            onClose: { showingPlaceDetails = false },
            onNameResolved: newPinCoordinate != nil ? { name in newPinName = name } : nil,
            onSaved: newPinCoordinate != nil ? {
                newPinCoordinate = nil
                newPinName = nil
            } : nil
        )
        .environmentObject(placeStore)
        .presentationBackgroundInteraction(.enabled)
    }

    // MARK: - Map Interaction

    private func handleAnnotationSelected(_ tag: String) {
        if tag == "new-place" {
            showingPlaceDetails = true
            if let coord = newPinCoordinate { centerAboveSheet(coord) }
        } else if let place = placeStore.places.first(where: { $0.id.uuidString == tag }) {
            selectedPlace = place
            selectedMapItem = nil
            newPinCoordinate = nil
            selectedSearchResult = nil
            showingPlaceDetails = true
            centerAboveSheet(place.coordinate)
        } else if let item = selectedSearchResult,
                  item.identifier?.rawValue == tag || tag == "search-result"
        {
            showingPlaceDetails = true
            centerAboveSheet(item.location.coordinate)
        }
    }

    private func centerAboveSheet(_ coordinate: CLLocationCoordinate2D) {
        let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let newCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.3,
            longitude: coordinate.longitude
        )
        cameraCommand = CameraCommand(
            action: .setRegion(MKCoordinateRegion(center: newCenter, span: span))
        )
    }

    @MainActor
    private func fetchResolvedCategories() async {
        await withTaskGroup(of: (UUID, MKPointOfInterestCategory?).self) { group in
            for place in placeStore.places {
                guard let mapItemId = place.mapItemId,
                      resolvedCategories[place.id] == nil
                else { continue }
                group.addTask {
                    let item = try? await MKMapItemRequest(
                        mapItemIdentifier: mapItemId
                    ).mapItem
                    return (place.id, item?.pointOfInterestCategory)
                }
            }
            for await (id, category) in group {
                if let category { resolvedCategories[id] = category }
            }
        }
    }
}
