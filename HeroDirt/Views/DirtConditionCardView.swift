import SwiftUI

struct DirtConditionCardView: View {
    let result: DirtConditionResult
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 16) {
            header
            conditionRow

            if showDetails {
                detailSection
            }

            Divider()

            Text(
                "Based on a soil moisture balance model using rainfall and evapotranspiration data. Actual conditions vary by shade, aspect, and trail surface."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: .cornerMedium)
        )
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Text("Dirt Conditions")
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text("Estimate")
                .font(.caption)
                .foregroundStyle(.secondary)
            if result.moistureIndex != nil {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        showDetails.toggle()
                    }
                } label: {
                    Image(
                        systemName: showDetails
                            ? "info.circle.fill" : "info.circle"
                    )
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showDetails ? "Hide details" : "Show details")
            }
        }
    }

    private var conditionRow: some View {
        HStack(spacing: 16) {
            Image(systemName: result.condition.icon)
                .font(.system(size: 36))
                .foregroundStyle(result.condition.color)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.condition.label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(result.condition.color)
                Text(result.condition.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        if let index = result.moistureIndex,
            let soil = result.soil,
            let et0 = result.recentET0
        {
            Divider()
            HStack(spacing: 10) {
                detailTile(
                    label: "Moisture",
                    value: "\(Int(index * 100))%",
                    valueColor: result.condition.color
                )
                detailTile(
                    label: soil.isEstimated ? "Soil (est.)" : "Soil type",
                    value: soil.textureLabel
                )
                detailTile(
                    label: "Drying rate",
                    value: String(format: "%.1f mm/d", et0)
                )
            }
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
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
