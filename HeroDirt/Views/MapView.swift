import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject private var placeStore: PlaceStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate = CLLocationCoordinate2D()
    @State private var hasSelection = false
    @State private var sheetPresented = true
    @State private var showingPlaceDetails = false
    @State private var mapSelection: MapSelection<UUID>?
    @State private var selectedPlaceID: UUID?
    @State private var selectedMapItem: MKMapItem?

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearchFocused = false

    @State private var resolvedCategories: [UUID: MKPointOfInterestCategory] = [:]

    @StateObject private var gridService = RainfallGridService()
    @State private var overlayVisible = false
    @State private var overlayTimeframe: RainfallTimeframe = .threeDays
    @State private var overlayOpacity: Double = 0.3
    @State private var cameraChangeCount = 0
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var containerHeight: CGFloat = 800

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom], selection: $mapSelection) {
                UserAnnotation()

                if hasSelection {
                    Marker("Selected", coordinate: selectedCoordinate)
                        .tint(.blue)
                }

                ForEach(placeStore.places) { place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                        Button {
                            selectedCoordinate = place.coordinate
                            selectedPlaceID = place.id
                            selectedMapItem = nil
                            hasSelection = false
                            showingPlaceDetails = true
                        } label: {
                            let category = resolvedCategories[place.id]
                            ZStack {
                                Circle()
                                    .fill(category?.iconColor ?? .orange)
                                    .frame(width: 32, height: 32)
                                Image(systemName: category?.sfSymbol ?? "mappin")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { _ in
                if isSearchFocused {
                    isSearchFocused = false
                    searchResults = []
                }
            })
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag) = value,
                           let location = drag?.location,
                           let coordinate = proxy.convert(location, from: .local) {
                            selectedCoordinate = coordinate
                            selectedPlaceID = nil
                            selectedMapItem = nil
                            hasSelection = true
                            showingPlaceDetails = true
                        }
                    }
            )
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
            .overlay(alignment: .top) {
                MapSearchOverlay(
                    searchText: $searchText,
                    isSearchFocused: $isSearchFocused,
                    searchResults: $searchResults,
                    containerHeight: containerHeight,
                    onSearch: runSearch,
                    onSelectResult: selectSearchResult
                )
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    RainfallOverlayControls(
                        isVisible: $overlayVisible,
                        timeframe: $overlayTimeframe,
                        opacity: $overlayOpacity,
                        isLoading: gridService.isLoading
                    )

                    Button {
                        cameraPosition = .userLocation(fallback: .automatic)
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                            .frame(width: 44, height: 44)
                    }
                    .tint(.primary)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
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
            .onChange(of: isSearchFocused) { _, isFocused in
                if isFocused && showingPlaceDetails {
                    showingPlaceDetails = false
                    mapSelection = nil
                    hasSelection = false
                }
            }
            .onChange(of: showingPlaceDetails) { _, isShowing in
                if isShowing {
                    Task { @MainActor in centerAboveSheet(selectedCoordinate) }
                }
            }
            .onChange(of: overlayVisible) { _, visible in
                if visible {
                    gridService.refetch()
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in containerHeight = h }
                }
            }
        }
        .sheet(isPresented: $sheetPresented, onDismiss: {
            showingPlaceDetails = false
            mapSelection = nil
            hasSelection = false
            Task { @MainActor in sheetPresented = true }
        }) {
            if showingPlaceDetails {
                LocationRainfallSheet(
                    coordinate: selectedCoordinate,
                    placeID: selectedPlaceID,
                    mapItem: selectedMapItem,
                    onClose: {
                        showingPlaceDetails = false
                        mapSelection = nil
                        hasSelection = false
                    }
                )
                .environmentObject(placeStore)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled)
            } else {
                SavedPlacesView(onSelectPlace: { place in
                    selectedCoordinate = place.coordinate
                    selectedPlaceID = place.id
                    selectedMapItem = nil
                    hasSelection = false
                    showingPlaceDetails = true
                })
                .presentationDetents([.fraction(0.4), .medium, .large])
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled(true)
            }
        }
    }

    // MARK: - Map Interaction

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

    private func handleSelectionChange(_ newValue: MapSelection<UUID>?) {
        guard let selection = newValue else { return }

        if let feature = selection.feature {
            Task {
                if let item = try? await MKMapItemRequest(feature: feature).mapItem {
                    selectedCoordinate = item.location.coordinate
                    selectedPlaceID = nil
                    selectedMapItem = item
                    hasSelection = false
                    showingPlaceDetails = true
                }
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

    // MARK: - Search

    private func runSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = visibleRegion {
            request.region = region
        }
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems
        } catch {
            searchResults = []
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.location.coordinate
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        ))
        selectedCoordinate = coordinate
        selectedPlaceID = nil
        selectedMapItem = item
        hasSelection = true
        searchResults = []
        searchText = ""
        isSearchFocused = false
        showingPlaceDetails = true
    }
}
