import MapKit
import SwiftUI

struct POICategoryIcon: View {
    let category: MKPointOfInterestCategory?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(category?.iconColor ?? .orange)
                .frame(width: size, height: size)
            Image(systemName: category?.sfSymbol ?? "mappin")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}
