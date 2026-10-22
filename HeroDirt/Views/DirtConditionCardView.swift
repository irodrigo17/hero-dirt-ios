import SwiftUI

struct DirtConditionCardView: View {
    let result: DirtConditionResult
    var onCustomize: (() -> Void)? = nil
    var isOverridden: Bool = false
    @State private var showDetails = false

    var body: some View {
        CardContainer {
            header
            conditionRow

            if showDetails {
                detailSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            Text(
                "Our best guess from recent rain and how fast the ground dries out. Shade, slope, and trail surface make a big difference, so always respect trail closures."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Text("Trail Conditions")
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            if result.moistureIndex != nil {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showDetails ? "Less" : "Why?")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showDetails ? 180 : 0))
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showDetails ? "Hide details" : "Show details")
            } else {
                Text("Estimate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var conditionRow: some View {
        HStack(spacing: 16) {
            Image(systemName: result.condition.icon)
                .font(.system(size: 36))
                .foregroundStyle(result.condition.color)
                .symbolEffect(.bounce, value: result.condition.label)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.condition.label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(result.condition.color)
                Text(result.condition.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detailSection: some View {
        if let index = result.moistureIndex,
            let soil = result.soil,
            let et0 = result.recentET0
        {
            VStack(spacing: 12) {
                Divider()
                HStack(spacing: 10) {
                    detailTile(
                        label: "Wetness",
                        value: "\(Int((index * 100).rounded()))%",
                        valueColor: result.condition.color
                    )
                    detailTile(
                        label: isOverridden ? "Dirt (yours)" : (soil.isEstimated ? "Dirt (guess)" : "Dirt"),
                        value: soil.riderLabel
                    )
                    detailTile(
                        label: "Drying",
                        value: Self.dryingLabel(et0: et0)
                    )
                }
                if let onCustomize {
                    Button(action: onCustomize) {
                        Label(
                            isOverridden ? "Edit trail settings" : "Know this trail? Tune it",
                            systemImage: isOverridden ? "pencil.circle.fill" : "slider.horizontal.3"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// Turns reference evapotranspiration (mm/day) into a rider-friendly word.
    static func dryingLabel(et0: Double) -> String {
        switch et0 {
        case ..<1.5: return "Slow"
        case ..<3.5: return "Moderate"
        default: return "Fast"
        }
    }

    private func detailTile(
        label: String,
        value: String,
        valueColor: Color = .primary
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
