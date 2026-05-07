import SwiftUI

extension Double {
    func formatMillimeters() -> String {
        self < 10 ? String(format: "%.1f", self) : String(format: "%.0f", self)
    }
}

extension CGFloat {
    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 12
    static let cornerLarge: CGFloat = 16
}

struct CardHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
