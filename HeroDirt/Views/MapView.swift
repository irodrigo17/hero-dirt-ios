import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject private var placeStore: PlaceStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var newPinCoordinate: CLLocationCoordinate2D?
    @State private var sheetPresented = true
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showingPlaceDetails = false
    @State private var mapSelection: MapSelection<String>?
    @State private var selectedPlace: Place?
    @State private var selectedMapItem: MKMapItem?
    @State private var selectedSearchResult: MKMapItem?

    @State private var resolvedCategories: [UUID: MKPointOfInterestCategory] = [:]

    @StateObject private var gridService = RainfallGridService()
    @State private var overlayVisible = false
    @State private var overlayTimeframe: RainfallTimeframe = .threeDays
    @State private var overlayOpacity: Double = 0.3
    @State private var cameraChangeCount = 0
    @State private var visibleRegion: MKCoordinateRegion?

    private let collapsedDetent = PresentationDetent.fraction(0.09)

    @GestureState private var longPressDragLocation: CGPoint? = nil
    @GestureState private var longPressActivated: Bool = false

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom], selection: $mapSelection) {
                UserAnnotation()

                if let coord = newPinCoordinate {
                    Marker("New place", coordinate: coord)
                        .tint(.blue).tag(MapSelection("new-place"))
                }

                if let searchResult = selectedSearchResult {
                    Marker(
                        searchResult.name ?? "",
                        systemImage: searchResult.pointOfInterestCategory?.sfSymbol ?? "mappin",
                        coordinate: searchResult.location.coordinate
                    )
                    .tint(searchResult.pointOfInterestCategory?.iconColor ?? .orange)
                    .tag(MapSelection(searchResult.identifier?.rawValue ?? "search-result"))
                }

                ForEach(placeStore.places) { place in
                    let category = resolvedCategories[place.id]
                    Marker(place.name, systemImage: category?.sfSymbol ?? "mappin", coordinate: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                    .tint(category?.iconColor ?? .orange)
                    .tag(MapSelection(place.id.uuidString))
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($longPressDragLocation) { value, state, _ in state = value.location }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .updating($longPressActivated) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
            )
            .onChange(of: longPressActivated) { _, activated in
                guard activated,
                      let location = longPressDragLocation,
                      let coordinate = proxy.convert(location, from: .local) else { return }
                newPinCoordinate = coordinate
                selectedPlace = nil
                selectedMapItem = nil
                selectedSearchResult = nil
                withAnimation {
                    mapSelection = MapSelection("new-place")
                }
            }
            .onChange(of: mapSelection) { _, newValue in
                handleSelectionChange(newValue)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraChangeCount += 1
                visibleRegion = context.region
                if overlayVisible {
                    gridService.updateRegion(context.region)
                }
            }
            .overlay {
                rainfallImageOverlay(proxy: proxy)
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    RainfallOverlayControlsView(
                        isVisible: $overlayVisible,
                        timeframe: $overlayTimeframe,
                        opacity: $overlayOpacity,
                        isLoading: gridService.isLoading
                    )

                    Button {
                        cameraPosition = .userLocation(fallback: .automatic)
                        selectedDetent = collapsedDetent
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                            .frame(width: 44, height: 44)
                    }
                    .tint(.primary)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Center map on your location")
                }
                .padding(12)
            }
            .onAppear {
                if placeStore.places.isEmpty {
                    cameraPosition = .userLocation(fallback: .automatic)
                }
            }
            .task(id: placeStore.places.map(\.id)) {
                await fetchResolvedCategories()
            }
            .onChange(of: overlayVisible) { _, visible in
                if visible {
                    gridService.refetch()
                }
            }
        }
        .sheet(isPresented: $sheetPresented, onDismiss: {
            Task { @MainActor in sheetPresented = true }
        }) {
            SheetView(
                onSelectPlace: { place in
                    selectedPlace = place
                    selectedMapItem = nil
                    newPinCoordinate = nil
                    selectedSearchResult = nil
                    withAnimation(.spring(duration: 0.3)) {
                        mapSelection = MapSelection(place.id.uuidString)
                    }
                },
                onSelectSearchResult: { item in
                    selectedSearchResult = item
                    selectedMapItem = item
                    selectedPlace = nil
                    newPinCoordinate = nil
                    withAnimation(.spring(duration: 0.3)) {
                        mapSelection = MapSelection(item.identifier?.rawValue ?? "search-result")
                    }
                },
                onSearchFocusChanged: { focused in
                    selectedDetent = focused ? .large : .medium
                },
                visibleRegion: visibleRegion,
                selectedDetent: selectedDetent
            )
            .presentationDetents([collapsedDetent, .medium, .large], selection: $selectedDetent)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(true)
            .sheet(isPresented: $showingPlaceDetails, onDismiss: {
                withAnimation {
                    mapSelection = nil
                }
                selectedPlace = nil
                newPinCoordinate = nil
                selectedSearchResult = nil
                selectedMapItem = nil
                selectedDetent = .medium
            }) {
                PlaceDetailsView(
                    coordinate: selectedPlace?.coordinate
                               ?? selectedMapItem?.location.coordinate
                               ?? newPinCoordinate
                               ?? CLLocationCoordinate2D(),
                    placeID: selectedPlace?.id,
                    mapItem: selectedMapItem,
                    onClose: { showingPlaceDetails = false }
                )
                .environmentObject(placeStore)
                .presentationBackgroundInteraction(.enabled)
            }
        }
    }

    @State private var selectionTask: Task<Void, Never>?

    // MARK: - Map Interaction

    @MainActor
    private func fetchResolvedCategories() async {
        await withTaskGroup(of: (UUID, MKPointOfInterestCategory?).self) { group in
            for place in placeStore.places {
                guard let mapItemId = place.mapItemId, resolvedCategories[place.id] == nil else { continue }
                group.addTask {
                    let item = try? await MKMapItemRequest(mapItemIdentifier: mapItemId).mapItem
                    return (place.id, item?.pointOfInterestCategory)
                }
            }
            for await (id, category) in group {
                if let category {
                    resolvedCategories[id] = category
                }
            }
        }
    }

    private func handleSelectionChange(_ newValue: MapSelection<String>?) {
        selectionTask?.cancel()
        guard let selection = newValue else { return }

        selectionTask = Task { @MainActor in
            if let feature = selection.feature {
                if let item = try? await MKMapItemRequest(feature: feature).mapItem {
                    guard !Task.isCancelled else { return }
                    selectedMapItem = item
                    selectedPlace = nil
                    newPinCoordinate = nil
                    selectedSearchResult = nil
                    showingPlaceDetails = true
                    centerAboveSheet(item.location.coordinate)
                }
            } else if let place = placeStore.places.first(where: { $0.id.uuidString == selection.value }) {
                guard !Task.isCancelled else { return }
                selectedPlace = place
                selectedMapItem = nil
                newPinCoordinate = nil
                selectedSearchResult = nil
                showingPlaceDetails = true
                centerAboveSheet(place.coordinate)
            } else if let item = selectedSearchResult {
                guard !Task.isCancelled else { return }
                showingPlaceDetails = true
                centerAboveSheet(item.location.coordinate)
            } else if let newPinCoordinate = newPinCoordinate {
                guard !Task.isCancelled else { return }
                showingPlaceDetails = true
                centerAboveSheet(newPinCoordinate)
            }
        }
    }

    // 0.25 = half the sheet height (50% detent) expressed as a fraction of the latitude span
    private func centerAboveSheet(_ coordinate: CLLocationCoordinate2D) {
        let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let newCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.25,
            longitude: coordinate.longitude
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(MKCoordinateRegion(center: newCenter, span: span))
        }
    }

    // MARK: - Rainfall Overlay

    @ViewBuilder
    private func rainfallImageOverlay(proxy: MapProxy) -> some View {
        let _ = gridService.gridVersion
        let _ = cameraChangeCount

        if overlayVisible,
           let bounds = gridService.gridBounds,
           let image = gridService.rainfallImage(for: overlayTimeframe),
           let tl = proxy.convert(bounds.topLeft, to: .local),
           let br = proxy.convert(bounds.bottomRight, to: .local) {
            let width = br.x - tl.x
            let height = br.y - tl.y
            if width > 0, height > 0 {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                    .position(x: (tl.x + br.x) / 2, y: (tl.y + br.y) / 2)
                    .opacity(overlayOpacity)
                    .allowsHitTesting(false)
            }
        }
    }
}
