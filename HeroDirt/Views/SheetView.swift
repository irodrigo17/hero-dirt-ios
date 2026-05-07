import SwiftUI
import MapKit

struct SheetView: View {
    var onSelectPlace: (Place) -> Void = { _ in }
    var onSelectSearchResult: (MKMapItem) -> Void = { _ in }
    var onSearchFocusChanged: (Bool) -> Void = { _ in }
    var visibleRegion: MKCoordinateRegion? = nil
    var selectedDetent: PresentationDetent

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            SearchableContent(
                searchResults: searchResults,
                selectedDetent: selectedDetent,
                onSelectPlace: onSelectPlace,
                onSelectSearchResult: onSelectSearchResult,
                onIsSearchingChanged: onSearchFocusChanged
            )
            .navigationTitle("Saved places")
            .searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "Search places")
            .navigationBarTitleDisplayMode(.inline)
            .onSubmit(of: .search) {
                searchTask?.cancel()
                guard !searchText.isEmpty else { return }
                searchTask = Task { await runSearch(query: searchText) }
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

    private func runSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = visibleRegion {
            request.region = region
        }
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            searchResults = response.mapItems
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }
}

private struct SearchableContent: View {
    let searchResults: [MKMapItem]
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
                    onSelectResult: { item in
                        dismissSearch()
                        onSelectSearchResult(item)
                    }
                )
            } else {
                SavedPlacesListView(onSelectPlace: onSelectPlace, selectedDetent: selectedDetent)
            }
        }
        .onChange(of: isSearching) { _, newValue in
            onIsSearchingChanged(newValue)
        }
    }
}
