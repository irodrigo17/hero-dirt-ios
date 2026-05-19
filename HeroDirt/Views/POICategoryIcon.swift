import MapKit
import SwiftUI

struct POICategoryIcon: View {
    let category: MKPointOfInterestCategory?

    var body: some View {
        ZStack {
            Circle()
                .fill(category?.iconColor ?? Color(.systemPink))
                .frame(width: 36, height: 36)
            Image(systemName: category?.sfSymbol ?? "mappin")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}
