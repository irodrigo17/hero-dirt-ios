import SwiftUI

struct RainfallLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("mm")
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
                ForEach(
                    Array(RainfallColorScale.stops.dropFirst().enumerated()),
                    id: \.offset
                ) { _, stop in
                    Text(stop.label)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    if stop.label != RainfallColorScale.stops.last?.label {
                        Spacer(minLength: 2)
                    }
                }
            }
        }
    }
}
