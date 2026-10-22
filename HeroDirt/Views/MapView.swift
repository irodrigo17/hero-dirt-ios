import MapKit
import SwiftUI

struct MapView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    @EnvironmentObject private var mapItemCache: MapItemCache

    @State private var cameraCommand: CameraCommand?
    @State private var selectedAnnotation: AnnotationSelection?
    @State private var newPinCoordinate: CLLocationCoordinate2D?
    @State private var newPinName: String?
    @State private var sheetPresented = true
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showingPlaceDetails = false
    @State private var selectedPlace: Place?
    @State private var selectedMapItem: MKMapItem?
    @State private var selectedSearchResult: MKMapItem?
    @State private var didInitialFit = false

    /// Side-by-side layout (sidebar + map) used in landscape and on wide
    /// windows such as the unfolded iPhone Duo in landscape.
    @State private var isSplit = false

    @StateObject private var gridService = RainfallGridService()
    @State private var overlayVisible = false
    @State private var overlayTimeframe: RainfallTimeframe = .threeDays
    @State private var overlayOpacity: Double = 0.3
    @State private var visibleRegion: MKCoordinateRegion?

    private let collapsedDetent = PresentationDetent.fraction(0.09)

    private var hasSelection: Bool {
        selectedPlace != nil || selectedMapItem != nil || newPinCoordinate != nil
    }

    /// How far below the visual center a focused coordinate should sit so it
    /// isn't hidden behind the bottom sheet. Zero in split layout.
    private var sheetBias: Double { isSplit ? 0 : 0.3 }

    static func prefersSplit(for size: CGSize) -> Bool {
        size.width > size.height && size.width >= 560
    }

    var body: some View {
        GeometryReader { proxy in
            let split = Self.prefersSplit(for: proxy.size)
            // `map` keeps the same structural position in both layouts so the
            // MKMapView (and its camera) survives rotation.
            HStack(spacing: 0) {
                if isSplit {
                    sidebar
                        .frame(width: min(max(proxy.size.width * 0.4, 300), 420))
                        .background(Color(.systemGroupedBackground).ignoresSafeArea())
                        .transition(.move(edge: .leading))
                    Divider()
                        .ignoresSafeArea()
                }
                map
            }
            .onAppear { applyLayout(split: split, animated: false) }
            .onChange(of: split) { _, newValue in applyLayout(split: newValue, animated: true) }
        }
        .onAppear {
            fitPlacesIfNeeded()
        }
        .onChange(of: placeStore.places.isEmpty) { _, _ in
            // Saved places can arrive from iCloud after launch (e.g. after a
            // reinstall); frame them once they do.
            fitPlacesIfNeeded()
        }
        .task(id: placeStore.places.map(\.id)) {
            mapItemCache.prefetch(places: placeStore.places)
        }
        .onChange(of: overlayVisible) { _, visible in
            Telemetry.signal(.rainMapToggled, ["visible": visible ? "true" : "false"])
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
                // The bottom sheet is permanent in the stacked layout.
                if !isSplit {
                    Task { @MainActor in sheetPresented = true }
                }
            }
        ) {
            mainSheet
        }
    }

    // MARK: - Layouts

    private var map: some View {
        UIKitMapView(
            places: placeStore.places,
            newPinCoordinate: newPinCoordinate,
            newPinTitle: newPinName,
            selectedSearchResult: selectedSearchResult,
            selectedAnnotation: selectedAnnotation,
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
                selectedAnnotation = .newPin
                showingPlaceDetails = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            },
            onAnnotationSelected: { handleAnnotationSelected($0) },
            onFeatureTapped: { item in
                selectedMapItem = item
                selectedPlace = nil
                newPinCoordinate = nil
                selectedSearchResult = nil
                showingPlaceDetails = true
                focus(on: item.location.coordinate)
            },
            onTap: {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            },
            onUserLocationAvailable: { coordinate in
                guard placeStore.places.isEmpty, !didInitialFit else { return }
                focus(on: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))
            }
        )
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        ZStack {
            sheetContent
            if hasSelection {
                placeDetails(onClose: closeDetails)
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .id(detailsIdentity)
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.35), value: hasSelection)
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        selectedPlace?.coordinate ?? selectedMapItem?.location.coordinate ?? newPinCoordinate
    }

    /// Changes when a different place is selected so the details view resets.
    private var detailsIdentity: String {
        if let selectedPlace { return selectedPlace.id.uuidString }
        if let selectedMapItem { return "item-\(selectedMapItem.hashValue)" }
        if let newPinCoordinate { return "pin-\(newPinCoordinate.latitude),\(newPinCoordinate.longitude)" }
        return "none"
    }

    private func applyLayout(split: Bool, animated: Bool) {
        guard split != isSplit || sheetPresented == split else { return }
        let hadDetails = hasSelection
        isSplit = split
        sheetPresented = !split
        if animated, let coordinate = selectedCoordinate {
            // Re-center the selection for the new layout once the map resizes.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                focus(on: coordinate)
            }
        }
        if split {
            showingPlaceDetails = false
        } else if hadDetails {
            // Present the details sheet once the bottom sheet is back.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if hasSelection && !isSplit { showingPlaceDetails = true }
            }
        }
    }

    // MARK: - Sheets

    private var sheetContent: some View {
        SheetView(
            onSelectPlace: { place in
                selectedPlace = place
                selectedMapItem = nil
                newPinCoordinate = nil
                selectedSearchResult = nil
                selectedAnnotation = .place(place)
                showingPlaceDetails = true
                focus(on: place.coordinate)
            },
            onSelectSearchResult: { item in
                Telemetry.signal(.searchResultSelected)
                selectedSearchResult = item
                selectedMapItem = item
                selectedPlace = nil
                newPinCoordinate = nil
                selectedAnnotation = .searchResult(item)
                showingPlaceDetails = true
                focus(on: item.location.coordinate)
            },
            onSearchFocusChanged: { focused in
                guard !isSplit else { return }
                selectedDetent = focused ? .large : .medium
            },
            visibleRegion: visibleRegion,
            selectedDetent: isSplit ? .large : selectedDetent,
            overlayVisible: $overlayVisible,
            overlayTimeframe: $overlayTimeframe,
            overlayOpacity: $overlayOpacity,
            isOverlayLoading: gridService.isLoading,
            onCenterLocation: {
                cameraCommand = CameraCommand(action: .centerOnUser)
                if !isSplit { selectedDetent = collapsedDetent }
            }
        )
    }

    private var mainSheet: some View {
        sheetContent
            .presentationDetents(
                [collapsedDetent, .medium, .large],
                selection: $selectedDetent
            )
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(true)
            .sheet(
                isPresented: $showingPlaceDetails,
                onDismiss: {
                    // Rotating into the split layout dismisses the sheets but
                    // keeps the selection, which moves into the sidebar.
                    guard !isSplit else { return }
                    closeDetails()
                }
            ) {
                placeDetails(onClose: { showingPlaceDetails = false })
                    .presentationBackgroundInteraction(.enabled)
            }
    }

    private func placeDetails(onClose: @escaping () -> Void) -> some View {
        PlaceDetailsView(
            coordinate: selectedCoordinate ?? CLLocationCoordinate2D(),
            placeID: selectedPlace?.id,
            mapItem: selectedMapItem,
            onClose: onClose,
            onNameResolved: newPinCoordinate != nil ? { name in newPinName = name } : nil,
            onSaved: newPinCoordinate != nil ? { place in
                selectedPlace = place
                newPinCoordinate = nil
                newPinName = nil
                selectedAnnotation = .place(place)
            } : nil,
            onUnsaved: { place in
                // Keep a pin where the place was so it doesn't vanish while
                // its details are still open.
                guard selectedMapItem == nil else { return }
                newPinCoordinate = place.coordinate
                newPinName = place.name
                selectedPlace = nil
                selectedAnnotation = .newPin
            }
        )
        .environmentObject(placeStore)
        .environmentObject(mapItemCache)
    }

    private func closeDetails() {
        showingPlaceDetails = false
        selectedAnnotation = nil
        selectedPlace = nil
        newPinCoordinate = nil
        newPinName = nil
        selectedSearchResult = nil
        selectedMapItem = nil
        selectedDetent = .medium
    }

    // MARK: - Map Interaction

    private func handleAnnotationSelected(_ selection: AnnotationSelection) {
        switch selection {
        case .place(let place):
            selectedPlace = place
            selectedMapItem = nil
            newPinCoordinate = nil
            selectedSearchResult = nil
            selectedAnnotation = .place(place)
            showingPlaceDetails = true
            focus(on: place.coordinate)
        case .newPin:
            showingPlaceDetails = true
            if let coord = newPinCoordinate { focus(on: coord) }
        case .searchResult(let item):
            showingPlaceDetails = true
            focus(on: item.location.coordinate)
        }
    }

    private func fitPlacesIfNeeded() {
        guard !didInitialFit, !placeStore.places.isEmpty else { return }
        didInitialFit = true
        cameraCommand = CameraCommand(action: .fitAllPlaces(placeStore.places, bias: sheetBias))
    }

    /// Moves the camera to a coordinate, keeping it clear of the bottom sheet.
    private func focus(on coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil) {
        let span = span ?? visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let newCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * sheetBias,
            longitude: coordinate.longitude
        )
        cameraCommand = CameraCommand(
            action: .setRegion(MKCoordinateRegion(center: newCenter, span: span))
        )
    }
}
