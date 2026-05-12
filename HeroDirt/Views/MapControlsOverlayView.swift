import SwiftUI

struct MapControlsOverlayView: View {
    @Binding var overlayVisible: Bool
    @Binding var overlayTimeframe: RainfallTimeframe
    @Binding var overlayOpacity: Double
    let isLoading: Bool
    var onCenterLocation: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            RainfallOverlayControlsView(
                isVisible: $overlayVisible,
                timeframe: $overlayTimeframe,
                opacity: $overlayOpacity,
                isLoading: isLoading
            )

            Button(action: onCenterLocation) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
            }
            .tint(.primary)
            .background(
                .ultraThickMaterial,
                in: RoundedRectangle(cornerRadius: .cornerSmall)
            )
            .accessibilityLabel("Center map on your location")
        }
        .padding(12)
    }
}
