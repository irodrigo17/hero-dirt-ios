import SwiftUI
import MapKit
import UIKit

// MARK: - SearchBar

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

// MARK: - MapSearchOverlay

struct MapSearchOverlay: View {
    @Binding var searchText: String
    @Binding var isSearchFocused: Bool
    @Binding var searchResults: [MKMapItem]
    let containerHeight: CGFloat
    let onSearch: (String) async -> Void
    let onSelectResult: (MKMapItem) -> Void

    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                isFocused: $isSearchFocused,
                onSearchTapped: {
                    searchTask?.cancel()
                    guard !searchText.isEmpty else { return }
                    searchTask = Task { await onSearch(searchText) }
                }
            )

            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults, id: \.self) { item in
                            Button {
                                onSelectResult(item)
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
                await onSearch(newValue)
            }
        }
    }
}

// MARK: - POICategoryIcon

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
