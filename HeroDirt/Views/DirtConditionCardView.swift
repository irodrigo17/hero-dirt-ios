import SwiftUI

struct DirtConditionCardView: View {
    let condition: DirtCondition

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Dirt Conditions")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Estimate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Image(systemName: condition.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(condition.color)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(condition.label)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(condition.color)
                    Text(condition.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
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
}
