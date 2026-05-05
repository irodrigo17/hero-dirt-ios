import SwiftUI
import MapKit
import UIKit

// MARK: - UISearchBar Wrapper

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onSearchTapped: () -> Void

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.delegate = context.coordinator
        searchBar.placeholder = "Search places"
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.backgroundColor = .tertiarySystemFill
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.setShowsCancelButton(isFocused, animated: true)
        if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UISearchBarDelegate {
        let parent: SearchBar

        init(_ parent: SearchBar) {
            self.parent = parent
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            parent.isFocused = true
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            parent.isFocused = false
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.text = ""
            parent.isFocused = false
            searchBar.resignFirstResponder()
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.onSearchTapped()
            searchBar.resignFirstResponder()
        }
    }
}

// MARK: - Map View

struct MapExploreView: View {
    @EnvironmentObject private var placeStore: PlaceStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate = CLLocationCoordinate2D()
    @State private var hasSelection = false
    @State private var showingSheet = false
    @State private var mapSelection: MapSelection<UUID>?
    @State private var selectedPlaceID: UUID?
    @State private var selectedMapItem: MKMapItem?

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearchFocused = false

    // Rainfall overlay
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
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(.orange)
                        .tag(place.id)
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
                            showingSheet = true
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
                searchBarOverlay
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
            .onChange(of: showingSheet) { _, isShowing in
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
        .sheet(isPresented: $showingSheet, onDismiss: { mapSelection = nil }) {
            LocationRainfallSheet(
                coordinate: selectedCoordinate,
                placeID: selectedPlaceID,
                mapItem: selectedMapItem
            )
            .environmentObject(placeStore)
            .presentationBackgroundInteraction(.enabled)
        }
    }

    // MARK: - Map Interaction

    private func handleSelectionChange(_ newValue: MapSelection<UUID>?) {
        guard let selection = newValue else { return }

        // Check if it's a saved place
        for place in placeStore.places {
            if selection == MapSelection(place.id) {
                mapSelection = nil
                selectedCoordinate = place.coordinate
                selectedPlaceID = place.id
                selectedMapItem = nil
                hasSelection = false
                showingSheet = true
                return
            }
        }

        // It's a map feature — leave mapSelection set so MapKit plays its native
        // selection animation, then resolve to MKMapItem for the sheet
        if let feature = selection.feature {
            Task {
                if let item = try? await MKMapItemRequest(feature: feature).mapItem {
                    selectedCoordinate = item.location.coordinate
                    selectedPlaceID = nil
                    selectedMapItem = item
                    hasSelection = false
                    showingSheet = true
                }
            }
        }
    }

    // 0.25 = half the sheet height (50% detent) expressed as a fraction of the latitude span
    private func centerAboveSheet(_ coordinate: CLLocationCoordinate2D) {
        guard let region = visibleRegion else { return }
        let newCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - region.span.latitudeDelta * 0.25,
            longitude: coordinate.longitude
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(MKCoordinateRegion(center: newCenter, span: region.span))
        }
    }

    // MARK: - Search Bar

    private var searchBarOverlay: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                isFocused: $isSearchFocused,
                onSearchTapped: { performSearch() }
            )

            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults, id: \.self) { item in
                            Button {
                                selectSearchResult(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    if let subtitle = item.address?.fullAddress, subtitle != item.name {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            
                            if item != searchResults.last {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
                .frame(maxHeight: containerHeight * 0.70)
                .fixedSize(horizontal: false, vertical: true)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            guard !newValue.isEmpty else {
                searchResults = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await runSearch(query: newValue)
            }
        }
    }

    // MARK: - Rainfall Image Overlay

    @ViewBuilder
    private func rainfallImageOverlay(proxy: MapProxy) -> some View {
        // Reference published properties to trigger re-renders
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

    private func performSearch() {
        Task { await runSearch(query: searchText) }
    }

    private func runSearch(query: String) async {
        searchResults = await runGeneralSearchResults(query: query, region: visibleRegion)
    }

    private func runGeneralSearchResults(query: String, region: MKCoordinateRegion?) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = region {
            request.region = region
        }
        request.resultTypes = .init(arrayLiteral: .pointOfInterest)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems
        } catch {
            return []
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
        showingSheet = true
    }
}
