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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
    @State private var showingAbout = false
    @State private var editMode: EditMode = .inactive
    @State private var renamingPlace: Place?
    @State private var editingName = ""

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
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
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
                .alert(
                    "Rename",
                    isPresented: Binding(get: { renamingPlace != nil }, set: { if !$0 { renamingPlace = nil } })
                ) {
                    TextField("Name", text: $editingName)
                    Button("Save") {
                        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                        if let place = renamingPlace, !trimmed.isEmpty {
                            placeStore.renamePlace(place, to: trimmed)
                        }
                        renamingPlace = nil
                    }
                    Button("Cancel", role: .cancel) { renamingPlace = nil }
                }
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
                isSearchLoading = false
                searchResults = []
                searchError = nil
            }
        }
        .onChange(of: placeStore.places.count) { _, count in
            if count < 2 { editMode = .inactive }
        }
        .onDisappear { searchTask?.cancel() }
        .onAppear {
            if incomingTrail != nil { openSharedTrail() } else { selectFirstIfSideBySide() }
        }
        .onChange(of: incomingTrail?.id) { _, _ in openSharedTrail() }
        .onChange(of: horizontalSizeClass) { _, _ in selectFirstIfSideBySide() }
    }

    private func openSharedTrail() {
        guard let incomingTrail else { return }
        let item = MKMapItem(location: CLLocation(latitude: incomingTrail.latitude, longitude: incomingTrail.longitude), address: nil)
        item.name = incomingTrail.name
        selection = .result(item)
        preferredCompactColumn = .detail
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
                            editingName = place.name
                            renamingPlace = place
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
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
                            Text(item.name ?? "Unknown")
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
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest, .physicalFeature]
            if let region = searchRegion {
                request.region = region
            }
            do {
                let items = try await MKLocalSearch(request: request).start().mapItems
                guard !Task.isCancelled else { return }
                searchResults = items
                isSearchLoading = false
                Telemetry.signal(.searchPerformed, ["results": "\(items.count)"])
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                isSearchLoading = false
                searchError = "Search is unavailable right now. Please try again."
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
