import SwiftUI
import UIKit

struct TrailSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let text: String
}

struct TrailShareSheet: UIViewControllerRepresentable {
    let payload: TrailSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [payload.image, payload.text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A native-rendered image that can be saved or shared without a backend.
struct TrailSharingCard: View {
    let name: String
    let summary: RainfallSummary
    let soil: SoilData?
    let sharedAt: Date
    @Environment(\.rainUnit) private var unit

    var body: some View {
        let condition = summary.dirtCondition(soil: soil)
        VStack(alignment: .leading, spacing: 22) {
            Label("HERO DIRT", systemImage: "mountain.2.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(ConditionPalette.hero)
            Text(name)
                .font(.title.bold())
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Image(systemName: condition.icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(condition.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(condition.label)
                        .font(.title.bold())
                        .foregroundStyle(condition.color)
                    Text(condition.shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            let strip = summary.strip(soil: soil)
            if strip.count > 1 {
                Text("THE WEEK AHEAD")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ConditionStrip(days: strip, style: .large)
            }
            HStack {
                Label("Last rain", systemImage: "cloud.rain")
                Spacer()
                Text(summary.lastRainText)
            }
            .font(.subheadline)
            HStack {
                Text("Recent rain · 7 days")
                Spacer()
                Text(unit.formatWithUnit(summary.last7Days))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Divider()
            Text("Estimated from weather and soil data.\nShared \(sharedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 420, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
