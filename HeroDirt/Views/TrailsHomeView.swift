import CoreLocation
import MapKit
import SwiftUI

/// Home screen: the rider's saved trails and how each one is doing. The map
/// is one tap away (toolbar). On wide windows this is a split view with the
/// selected trail's details on the right.
struct TrailsHomeView: View {
    var onShowMap: () -> Void = {}
    var incomingTrail: SharedTrail?

    @Environment(PlaceStore.self) private var placeStore
    @Environment(PlaceConditionsModel.self) private var conditions
    @Environment(\.weather) private var weather
    @Environment(\.sharedTrailResolver) private var sharedTrailResolver
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isOpeningSharedTrail = false
    @State private var sharedTrailError = false
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar
    @State private var selection: TrailSelection?
    /// Keep the trails list visible next to the details whenever the window
    /// is wide enough (unfolded iPhone Duo held tall included); otherwise
    /// SwiftUI would hide it behind a sidebar button in taller windows.
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearchLoading = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSearch: MKLocalSearch?
    @State private var showingAbout = false
    @State private var editMode: EditMode = .inactive

    enum TrailSelection: Hashable {
        case saved(UUID)
        case result(MKMapItem)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            list
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
                .navigationTitle("My Trails")
                .searchable(
                    text: $searchText,
                    isPresented: $isSearching,
                    placement: .automatic,
                    prompt: "Find trails, parks, places"
                )
                .onChange(of: searchText) { _, query in scheduleSearch(query) }
                .onSubmit(of: .search) { scheduleSearch(searchText, debounce: false) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingAbout = true
                        } label: {
                            Label("About Hero Dirt", systemImage: "info.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if placeStore.places.count > 1 {
                            EditButton().disabled(isSearching)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onShowMap) {
                            Label("Map", systemImage: "map")
                        }
                        .accessibilityLabel("Show map")
                    }
                }
                .sheet(isPresented: $showingAbout) { AboutView() }
        } detail: {
            NavigationStack {
                detail
            }
        }
        .environment(\.editMode, $editMode)
        .navigationSplitViewStyle(.balanced)
        .onChange(of: isSearching) { _, searching in
            if searching {
                editMode = .inactive
            } else {
                searchTask?.cancel()
                activeSearch?.cancel()
                activeSearch = nil
                isSearchLoading = false
                searchResults = []
                searchError = nil
            }
        }
        .onChange(of: placeStore.places.count) { _, count in
            if count < 2 { editMode = .inactive }
        }
        .onDisappear {
            searchTask?.cancel()
            activeSearch?.cancel()
            activeSearch = nil
        }
        .onAppear {
            if incomingTrail == nil { selectFirstIfSideBySide() }
        }
        .task(id: incomingTrail?.id) { await openSharedTrail() }
        .overlay {
            if isOpeningSharedTrail {
                ProgressView("Opening trail…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Couldn't Open Trail", isPresented: $sharedTrailError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Apple Maps couldn't retrieve this place. Check your connection and try opening the link again.")
        }
        .onChange(of: horizontalSizeClass) { _, _ in selectFirstIfSideBySide() }
    }

    private func openSharedTrail() async {
        guard let incomingTrail else { return }
        isOpeningSharedTrail = true
        sharedTrailError = false
        defer {
            if !Task.isCancelled { isOpeningSharedTrail = false }
        }
        do {
            let item = try await sharedTrailResolver.resolve(incomingTrail)
            guard !Task.isCancelled else { return }
            selection = .result(item)
            preferredCompactColumn = .detail
        } catch {
            guard !Task.isCancelled else { return }
            sharedTrailError = true
        }
    }

    /// With the list and details side by side, show the first trail instead
    /// of an empty pane.
    private func selectFirstIfSideBySide() {
        guard horizontalSizeClass == .regular, selection == nil,
              let first = placeStore.places.first
        else { return }
        selection = .saved(first.id)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        List(selection: $selection) {
            if isSearching {
                searchSection
            } else if placeStore.places.isEmpty {
                emptyState
            } else {
                ForEach(placeStore.places) { place in
                    NavigationLink(value: TrailSelection.saved(place.id)) {
                        TrailCard(
                            place: place,
                            rainfall: conditions.rainfall[place.id],
                            isLoading: conditions.loading.contains(place.id),
                            error: conditions.errors[place.id]
                        )
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            DrivingDirections.open(to: place)
                        } label: {
                            Label("Directions", systemImage: "car.fill")
                        }
                        .accessibilityHint("Opens directions in your default navigation app")
                        .tint(.blue)
                    }
                }
                .onMove { placeStore.movePlaces(from: $0, to: $1) }
                .onDelete { placeStore.removePlaces(at: $0) }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await conditions.refresh(placeStore.places, weather: weather)
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if searchResults.isEmpty {
            SearchStatusView(query: searchText, isLoading: isSearchLoading, error: searchError)
                .listRowSeparator(.hidden)
        } else {
            if isSearchLoading { ProgressView("Searching…").listRowSeparator(.hidden) }
            ForEach(searchResults, id: \.self) { item in
                NavigationLink(value: TrailSelection.result(item)) {
                    HStack(spacing: 10) {
                        POICategoryIcon(category: item.pointOfInterestCategory)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? String(localized: "Unknown"))
                                .font(.subheadline)
                            if let subtitle = item.addressRepresentations?.cityWithContext
                                ?? item.pointOfInterestCategory?.displayName
                            {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .disabled(isSearchLoading)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No trails yet", systemImage: "bicycle")
        } description: {
            Text("Search for the trails and parks you ride, or find them on the map, and save them to see when they're ridable.")
        } actions: {
            // Same size and font for both; Find Trails is the filled primary.
            Button { isSearching = true } label: {
                Text("Find Trails").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .font(.body.weight(.semibold))

            Button(action: onShowMap) {
                Text("Open Map").frame(minWidth: 160)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .font(.body.weight(.semibold))
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .saved(let id):
            if let place = placeStore.places.first(where: { $0.id == id }) {
                PlaceDetailsView(coordinate: place.coordinate, placeID: place.id, style: .pushed)
                    .id(place.id)
            } else {
                noSelection
            }
        case .result(let item):
            PlaceDetailsView(coordinate: item.location.coordinate, mapItem: item, style: .pushed)
                .id(ObjectIdentifier(item))
        case nil:
            noSelection
        }
    }

    private var noSelection: some View {
        ContentUnavailableView(
            "Pick a trail",
            systemImage: "mountain.2",
            description: Text("Choose a trail to see its conditions and the week ahead.")
        )
    }

    // MARK: - Search

    private func scheduleSearch(_ query: String, debounce: Bool = true) {
        searchTask?.cancel()
        activeSearch?.cancel()
        activeSearch = nil
        searchError = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearchLoading = false
            return
        }
        isSearchLoading = true
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            let request = OutdoorPlaceSearch.request(query: query, region: searchRegion)
            do {
                let operation = MKLocalSearch(request: request)
                activeSearch = operation
                let response = try await operation.start()
                let items = OutdoorPlaceSearch.results(from: response.mapItems)
                guard !Task.isCancelled else { return }
                activeSearch = nil
                searchResults = items
                isSearchLoading = false
                Telemetry.signal(.searchPerformed, ["results": "\(items.count)"])
            } catch {
                guard !Task.isCancelled else { return }
                activeSearch = nil
                searchResults = []
                isSearchLoading = false
                searchError = OutdoorPlaceSearch.isNoResults(error)
                    ? nil : String(localized: "Search is unavailable right now. Please try again.")
            }
        }
    }

    /// Bias search toward the rider's area: their location, else their trails.
    private var searchRegion: MKCoordinateRegion? {
        let span = MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        if let location = CLLocationManager().location {
            return MKCoordinateRegion(center: location.coordinate, span: span)
        }
        guard let first = placeStore.places.first else { return nil }
        return MKCoordinateRegion(center: first.coordinate, span: span)
    }
}

#Preview("My Trails") {
    TrailsHomeView()
        .previewEnvironment()
}

#Preview("Empty") {
    TrailsHomeView()
        .previewEnvironment(store: SampleData.placeStore([]))
}
