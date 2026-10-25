import MapKit
import SwiftUI

struct SheetView: View {
    var onSelectPlace: (Place) -> Void = { _ in }
    var onSelectSearchResult: (MKMapItem) -> Void = { _ in }
    var onSearchFocusChanged: (Bool) -> Void = { _ in }
    var visibleRegion: MKCoordinateRegion? = nil
    var selectedDetent: PresentationDetent

    @Binding var overlayVisible: Bool
    @Binding var overlayTimeframe: RainfallTimeframe
    @Binding var overlayOpacity: Double
    let isOverlayLoading: Bool
    var onCenterLocation: () -> Void = {}
    /// Switches to the trails list home (nil hides the button).
    var onShowList: (() -> Void)? = nil
    /// False in the split layout, where the map has its own floating controls.
    var showsMapActions: Bool = true

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearchLoading = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSearch: MKLocalSearch?
    @State private var showingAbout = false
    @State private var showingOverlayControls = false

    var body: some View {
        NavigationStack {
            SearchableContent(
                searchResults: searchResults,
                query: searchText,
                isLoading: isSearchLoading,
                error: searchError,
                selectedDetent: selectedDetent,
                onSelectPlace: onSelectPlace,
                onSelectSearchResult: onSelectSearchResult,
                onIsSearchingChanged: { active in
                    if !active {
                        searchTask?.cancel()
                        activeSearch?.cancel()
                        activeSearch = nil
                        isSearchLoading = false
                        searchResults = []
                        searchError = nil
                    }
                    onSearchFocusChanged(active)
                }
            )
            .navigationTitle("My Trails")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Find trails, parks, places"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsMapActions {
                    mapActionsToolbar
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingOverlayControls) {
                RainfallOverlaySheet(
                    isVisible: $overlayVisible,
                    timeframe: $overlayTimeframe,
                    opacity: $overlayOpacity,
                    isLoading: isOverlayLoading
                )
                .presentationDetents([.fraction(0.7)])
                .presentationBackgroundInteraction(.enabled)
            }
            .onSubmit(of: .search) {
                searchTask?.cancel()
                activeSearch?.cancel()
                activeSearch = nil
                guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                isSearchLoading = true
                searchError = nil
                searchTask = Task { await runSearch(query: searchText) }
            }
        }
        .onDisappear {
            searchTask?.cancel()
            activeSearch?.cancel()
            activeSearch = nil
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            activeSearch?.cancel()
            activeSearch = nil
            searchError = nil
            guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                searchResults = []
                isSearchLoading = false
                return
            }
            isSearchLoading = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await runSearch(query: newValue)
            }
        }
    }

    @ToolbarContentBuilder
    private var mapActionsToolbar: some ToolbarContent {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if let onShowList {
                        Button(action: onShowList) {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Show trails list")
                    } else {
                        Button {
                            showingAbout = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel("About Hero Dirt")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingOverlayControls = true
                    } label: {
                        ZStack {
                            if isOverlayLoading {
                                ProgressView().controlSize(.small)
                            }
                            Image(systemName: overlayVisible ? "cloud.rain.fill" : "cloud.rain")
                                .opacity(isOverlayLoading ? 0 : 1)
                        }
                    }
                    .tint(overlayVisible ? .blue : nil)
                    .accessibilityLabel("Rain map")

                    Button(action: onCenterLocation) {
                        Image(systemName: "location.fill")
                    }
                    .accessibilityLabel("Center map on your location")
                }
    }

    private func runSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = visibleRegion {
            request.region = region
        }
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        do {
            let operation = MKLocalSearch(request: request)
            activeSearch = operation
            let response = try await operation.start()
            guard !Task.isCancelled else { return }
            activeSearch = nil
            searchResults = response.mapItems
            isSearchLoading = false
            Telemetry.signal(.searchPerformed, ["results": "\(response.mapItems.count)"])
        } catch {
            guard !Task.isCancelled else { return }
            activeSearch = nil
            searchResults = []
            isSearchLoading = false
            searchError = String(localized: "Search is unavailable right now. Please try again.")
        }
    }
}

private struct SearchableContent: View {
    let searchResults: [MKMapItem]
    let query: String
    let isLoading: Bool
    let error: String?
    let selectedDetent: PresentationDetent
    var onSelectPlace: (Place) -> Void
    var onSelectSearchResult: (MKMapItem) -> Void
    var onIsSearchingChanged: (Bool) -> Void

    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        Group {
            if isSearching {
                SearchResultsView(
                    searchResults: searchResults,
                    query: query,
                    isLoading: isLoading,
                    error: error,
                    onSelectResult: { item in
                        dismissSearch()
                        onSelectSearchResult(item)
                    }
                )
            } else {
                SavedPlacesListView(
                    onSelectPlace: onSelectPlace,
                    selectedDetent: selectedDetent
                )
            }
        }
        .onChange(of: isSearching) { _, newValue in
            onIsSearchingChanged(newValue)
        }
        .onChange(of: selectedDetent) { _, newDetent in
            if isSearching && newDetent == .medium {
                dismissSearch()
            }
        }
    }
}
