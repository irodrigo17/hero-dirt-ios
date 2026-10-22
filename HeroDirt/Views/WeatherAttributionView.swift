import SwiftUI
import WeatherKit

/// Apple Weather trademark and legal link, required wherever WeatherKit data
/// is shown. https://developer.apple.com/weatherkit/get-started/#attribution
struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        HStack(spacing: 6) {
            if let attribution {
                AsyncImage(
                    url: colorScheme == .dark
                        ? attribution.combinedMarkDarkURL
                        : attribution.combinedMarkLightURL
                ) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(attribution.serviceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 12)
                .accessibilityLabel(attribution.serviceName)

                Spacer(minLength: 8)

                Link("Legal", destination: attribution.legalPageURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear.frame(height: 12)
            }
        }
        .task {
            attribution = await Self.load()
        }
    }

    private static var cached: WeatherAttribution?

    @MainActor
    private static func load() async -> WeatherAttribution? {
        if let cached { return cached }
        let value = try? await WeatherKit.WeatherService.shared.attribution
        cached = value
        return value
    }
}
