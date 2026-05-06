import SwiftUI
import MapKit

struct SearchResultsView: View {
    let searchResults: [MKMapItem]
    var onSelectResult: (MKMapItem) -> Void = { _ in }

    var body: some View {
        if searchResults.isEmpty {
            Spacer()
        } else {
            List {
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
                                if let subtitle = item.placemark.title, subtitle != item.name {
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
