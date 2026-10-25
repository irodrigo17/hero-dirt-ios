import MapKit
import SwiftUI

struct SearchResultsView: View {
    let searchResults: [MKMapItem]
    var query = ""
    var isLoading = false
    var error: String?
    var onSelectResult: (MKMapItem) -> Void = { _ in }

    var body: some View {
        if searchResults.isEmpty {
            SearchStatusView(query: query, isLoading: isLoading, error: error)
        } else {
            List {
                if isLoading { ProgressView("Searching…") }
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        onSelectResult(item)
                    } label: {
                        HStack(spacing: 10) {
                            POICategoryIcon(
                                category: item.pointOfInterestCategory
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? String(localized: "Unknown"))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                let subtitle =
                                    item.addressRepresentations?.cityWithContext
                                    ?? item.pointOfInterestCategory?.displayName
                                if let subtitle, subtitle != item.name {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct SearchStatusView: View {
    let query: String
    let isLoading: Bool
    let error: String?

    var body: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView("Searching…")
                Spacer()
            }
            .padding(.vertical, 40)
        } else if let error {
            ContentUnavailableView("Couldn't Search", systemImage: "wifi.exclamationmark", description: Text(error))
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("Find Trails and Parks", systemImage: "magnifyingglass", description: Text("Enter a place name, or use the keyboard microphone to dictate your search."))
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}
