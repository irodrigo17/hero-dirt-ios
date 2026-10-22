import SwiftUI

struct RainfallLegendView: View {
    @Environment(\.rainUnit) private var unit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(unit.symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            LinearGradient(
                stops: RainfallColorScale.gradientStops,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            HStack {
                let visible = Array(RainfallColorScale.stops.dropFirst())
                ForEach(Array(visible.enumerated()), id: \.offset) { index, stop in
                    Text(stop.label(for: unit))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if index < visible.count - 1 {
                        Spacer(minLength: 2)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rain map legend, from light green for a trace of rain to purple for heavy rain")
    }
}
