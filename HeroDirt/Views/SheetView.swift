import SwiftUI
import MapKit

struct SheetView: View {
    var onSelectPlace: (Place) -> Void = { _ in }
    var onSelectSearchResult: (MKMapItem) -> Void = { _ in }
    var onSearchFocusChanged: (Bool) -> Void = { _ in }
    var visibleRegion: MKCoordinateRegion? = nil
    var selectedDetent: PresentationDetent

    @State private var searchText = ""
    @State private var isSearchFocused = false
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                isFocused: $isSearchFocused,
                onSearchTapped: {
                    searchTask?.cancel()
                    guard !searchText.isEmpty else { return }
                    searchTask = Task { await runSearch(query: searchText) }
                }
            )
            .padding(8)
            if isSearchFocused {
                SearchResultsView(
                    searchResults: searchResults,
                    onSelectResult: { item in
                        isSearchFocused = false
                        onSelectSearchResult(item)
                    }
                )
            } else {
                SavedPlacesListView(onSelectPlace: onSelectPlace, selectedDetent: selectedDetent)
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            onSearchFocusChanged(focused)
            if !focused {
                searchText = ""
                searchResults = []
                searchTask?.cancel()
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
            searchResults = response.mapItems
        } catch {
            searchResults = []
        }
    }
}
