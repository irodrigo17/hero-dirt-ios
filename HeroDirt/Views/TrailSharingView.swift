import LinkPresentation
import SwiftUI
import UIKit

struct TrailSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let text: String
    let url: URL
    let title: String
}

struct TrailShareSheet: UIViewControllerRepresentable {
    let payload: TrailSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [
            TrailShareItemSource(payload: payload, kind: .link),
            TrailShareItemSource(payload: payload, kind: .image),
            TrailShareItemSource(payload: payload, kind: .mailNote)
        ], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Supply one rich link to Messages. Alternate representations retain image
/// saving and the email fallback without adding extra Messages attachments.
@MainActor
// UIKit guarantees these delegate callbacks run on the main thread.
final class TrailShareItemSource: NSObject, @preconcurrency UIActivityItemSource {
    enum Kind { case link, image, mailNote }
    let payload: TrailSharePayload
    let kind: Kind
    private let metadata: LPLinkMetadata?

    init(payload: TrailSharePayload, kind: Kind) {
        self.payload = payload
        self.kind = kind
        if kind == .link {
            let metadata = LPLinkMetadata()
            metadata.originalURL = payload.url
            metadata.url = payload.url
            metadata.title = payload.title
            metadata.imageProvider = NSItemProvider(object: payload.image)
            if let icon = UIImage(systemName: "mountain.2.fill") {
                metadata.iconProvider = NSItemProvider(object: icon)
            }
            self.metadata = metadata
        } else {
            metadata = nil
        }
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        switch kind {
        case .link: payload.url
        case .image: payload.image
        case .mailNote: payload.text
        }
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        switch kind {
        case .link:
            if let activityType, [.saveToCameraRoll, .mail, .print, .assignToContact].contains(activityType) { return nil }
            return payload.url
        case .image:
            if let activityType, [.message, .copyToPasteboard, .airDrop, .addToReadingList].contains(activityType) { return nil }
            return payload.image
        case .mailNote:
            return activityType == .mail ? payload.text : nil
        }
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        payload.title
    }
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
