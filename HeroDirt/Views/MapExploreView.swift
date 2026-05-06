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
    @State private var sheetPresented = true
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showingPlaceDetails = false
    @State private var mapSelection: MapSelection<UUID>?
    @State private var selectedPlaceID: UUID?
    @State private var selectedMapItem: MKMapItem?

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearchFocused = false

    @State private var resolvedCategories: [UUID: MKPointOfInterestCategory] = [:]

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
                .presentationDetents([.fraction(0.25), .medium, .large], selection: $selectedDetent)
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

        // It's a map feature — leave mapSelection set so MapKit plays its native
        // selection animation, then resolve to MKMapItem for the sheet
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
                                HStack(spacing: 10) {
                                    POICategoryIcon(category: item.pointOfInterestCategory)
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
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if item != searchResults.last {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
                .frame(maxHeight: containerHeight * 0.69)
                .fixedSize(horizontal: false, vertical: true)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        request.resultTypes = [.pointOfInterest, .physicalFeature]
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
        showingPlaceDetails = true
    }
}

// MARK: - POI Category Icon

private struct POICategoryIcon: View {
    let category: MKPointOfInterestCategory?

    var body: some View {
        ZStack {
            Circle()
                .fill(category?.iconColor ?? Color(.systemPink))
                .frame(width: 36, height: 36)
            Image(systemName: category?.sfSymbol ?? "mappin")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - MKPointOfInterestCategory display helpers

extension MKPointOfInterestCategory {
    var displayName: String {
        switch self {
        case .amusementPark:   return "Amusement Park"
        case .aquarium:        return "Aquarium"
        case .atm:             return "ATM"
        case .bakery:          return "Bakery"
        case .bank:            return "Bank"
        case .beach:           return "Beach"
        case .brewery:         return "Brewery"
        case .cafe:            return "Café"
        case .campground:      return "Campground"
        case .carRental:       return "Car Rental"
        case .evCharger:       return "EV Charger"
        case .fireStation:     return "Fire Station"
        case .fitnessCenter:   return "Fitness Center"
        case .foodMarket:      return "Food Market"
        case .gasStation:      return "Gas Station"
        case .hospital:        return "Hospital"
        case .hotel:           return "Hotel"
        case .laundry:         return "Laundry"
        case .library:         return "Library"
        case .marina:          return "Marina"
        case .movieTheater:    return "Movie Theater"
        case .museum:          return "Museum"
        case .nationalPark:    return "National Park"
        case .nightlife:       return "Nightlife"
        case .park:            return "Park"
        case .parking:         return "Parking"
        case .pharmacy:        return "Pharmacy"
        case .police:          return "Police"
        case .postOffice:      return "Post Office"
        case .publicTransport: return "Public Transport"
        case .restaurant:      return "Restaurant"
        case .restroom:        return "Restroom"
        case .school:          return "School"
        case .stadium:         return "Stadium"
        case .store:           return "Store"
        case .theater:         return "Theater"
        case .university:      return "University"
        case .winery:          return "Winery"
        case .zoo:             return "Zoo"
        default:
            let raw = rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
            return raw.unicodeScalars.reduce("") { result, scalar in
                let char = Character(scalar)
                return result.isEmpty ? String(char) : char.isUppercase ? "\(result) \(char)" : "\(result)\(char)"
            }
        }
    }

    var sfSymbol: String {
        switch self {
        case .amusementPark:   return "ferriswheel"
        case .aquarium:        return "fish.fill"
        case .atm:             return "banknote.fill"
        case .bakery:          return "birthday.cake.fill"
        case .bank:            return "building.columns.fill"
        case .beach:           return "beach.umbrella.fill"
        case .brewery:         return "mug.fill"
        case .cafe:            return "cup.and.saucer.fill"
        case .campground:      return "tent.fill"
        case .carRental:       return "car.fill"
        case .evCharger:       return "bolt.car.fill"
        case .fireStation:     return "flame.fill"
        case .fitnessCenter:   return "figure.run"
        case .foodMarket:      return "basket.fill"
        case .gasStation:      return "fuelpump.fill"
        case .hospital:        return "cross.fill"
        case .hotel:           return "bed.double.fill"
        case .laundry:         return "washer.fill"
        case .library:         return "books.vertical.fill"
        case .marina:          return "sailboat.fill"
        case .movieTheater:    return "film.fill"
        case .museum:          return "building.columns.fill"
        case .nationalPark:    return "tree.fill"
        case .nightlife:       return "moon.stars.fill"
        case .park:            return "tree.fill"
        case .parking:         return "p.circle.fill"
        case .pharmacy:        return "pills.fill"
        case .police:          return "shield.fill"
        case .postOffice:      return "envelope.fill"
        case .publicTransport: return "tram.fill"
        case .restaurant:      return "fork.knife"
        case .restroom:        return "toilet.fill"
        case .school:          return "graduationcap.fill"
        case .stadium:         return "sportscourt.fill"
        case .store:           return "cart.fill"
        case .theater:         return "theatermasks.fill"
        case .university:      return "building.columns.fill"
        case .winery:          return "wineglass.fill"
        case .zoo:             return "pawprint.fill"
        default:               return "mappin"
        }
    }

    var iconColor: Color {
        switch self {
        case .park, .nationalPark, .campground, .zoo:
            return .green
        case .hiking:
            return Color(
                red: 0.2,
                green: 0.6,
                blue: 0.2
            )
        case .beach, .marina:
            return .teal
        case .restaurant, .foodMarket, .bakery:
            return .orange
        case .cafe, .brewery, .winery:
            return Color(
                red: 0.6,
                green: 0.3,
                blue: 0.1
            )
        case .nightlife, .movieTheater, .theater, .museum, .amusementPark:
            return .purple
        case .hospital, .pharmacy, .fireStation:
            return .red
        case .hotel, .publicTransport, .parking, .store, .carRental, .evCharger, .police, .postOffice, .laundry, .marina:
            return .blue
        case .school, .university, .library:
            return Color(
                red: 0.5,
                green: 0.35,
                blue: 0.1
            )
        case .fitnessCenter, .stadium:
            return Color(
                red: 0.9,
                green: 0.4,
                blue: 0.0
            )
        case .gasStation, .atm, .bank, .restroom:
            return Color(
                .systemGray
            )
        default:
            return Color(
                .systemPink
            )
        }
    }
}
