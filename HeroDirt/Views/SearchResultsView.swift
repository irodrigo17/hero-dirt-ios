import MapKit
import SwiftUI

struct SearchResultsView: View {
    let searchResults: [MKMapItem]
    var onSelectResult: (MKMapItem) -> Void = { _ in }

    var body: some View {
        if searchResults.isEmpty {
            ContentUnavailableView(
                "No results found",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term")
            )
        } else {
            List {
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        onSelectResult(item)
                    } label: {
                        HStack(spacing: 10) {
                            POICategoryIcon(
                                category: item.pointOfInterestCategory
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
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
                }
            }
            .listStyle(.plain)
        }
    }
}
