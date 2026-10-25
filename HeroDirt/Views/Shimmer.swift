import SwiftUI

// MARK: - Shimmer

/// Sweeps a soft highlight across the view, used on skeleton placeholders while
/// data loads. Respects Reduce Motion by falling back to a gentle pulse.
struct Shimmer: ViewModifier {
    var active: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if !active {
            content
        } else if reduceMotion {
            content
                .opacity(phase > 0 ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(), value: phase)
                .onAppear { phase = 1 }
        } else {
            content
                .overlay {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.45), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(width * 0.6, 80))
                        .offset(x: phase * (width + max(width * 0.6, 80)) - max(width * 0.6, 80) / 2)
                        .blendMode(.plusLighter)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

extension View {
    func shimmering(active: Bool = true) -> some View {
        modifier(Shimmer(active: active))
    }
}

// MARK: - Skeleton pieces

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = .cornerSmall

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Mirrors the default detail cards, in the same order and with the same
/// spacing. Action buttons are already rendered by PlaceDetailsView.
struct PlaceDetailsSkeleton: View {
    var body: some View {
        VStack(spacing: 20) {
            CardContainer {
                SkeletonCardHeader()
                HStack(spacing: 16) {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 28)
                        SkeletonBlock(height: 16)
                        SkeletonBlock(height: 16)
                    }
                }
                Divider()
                VStack(spacing: 6) {
                    SkeletonBlock(height: 12)
                    SkeletonBlock(height: 12)
                    SkeletonBlock(height: 12)
                }
            }

            CardContainer {
                SkeletonCardHeader()
                SkeletonBlock(height: 24)
                SkeletonConditionStrip(isLarge: true)
            }

            CardContainer {
                SkeletonCardHeader()
                SkeletonBlock(height: 140, cornerRadius: 4)
                SkeletonBlock(height: 70, cornerRadius: 4)
            }

            SkeletonRainCard(isForecast: false)
            SkeletonRainCard(isForecast: true)
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading trail conditions")
    }
}

/// Placeholder for the row's summary and compact eight-day strip. The real
/// place name and a separate badge placeholder stay in the row's header.
struct PlaceRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(height: 16)
            SkeletonConditionStrip()
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

private struct SkeletonCardHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            SkeletonBlock(height: 17)
            SkeletonBlock(height: 12)
                .frame(maxWidth: 90)
        }
    }
}

/// Today plus seven forecast days, matching ConditionStrip's two sizes.
private struct SkeletonConditionStrip: View {
    var isLarge = false

    var body: some View {
        HStack(spacing: isLarge ? 6 : 4) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(spacing: isLarge ? 5 : 3) {
                    SkeletonBlock(height: isLarge ? 14 : 12, cornerRadius: 3)
                        .padding(.horizontal, 4)
                    SkeletonBlock(height: isLarge ? 30 : 10, cornerRadius: isLarge ? 8 : 4)
                    if isLarge {
                        SkeletonBlock(height: 12, cornerRadius: 3)
                            .padding(.horizontal, 5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct SkeletonRainCard: View {
    var isForecast: Bool

    var body: some View {
        CardContainer {
            SkeletonCardHeader()
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 4) {
                        SkeletonBlock(height: 12, cornerRadius: 3)
                        SkeletonBlock(height: 22, cornerRadius: 4)
                        SkeletonBlock(height: 12, cornerRadius: 3)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: .cornerSmall + 2))
                }
            }
            if !isForecast {
                Divider()
                HStack(spacing: 16) {
                    SkeletonBlock(height: 16)
                    SkeletonBlock(height: 16)
                        .frame(maxWidth: 100)
                }
            }
            SkeletonBlock(width: 140, height: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isForecast {
                SkeletonBlock(height: 12)
            }
        }
    }
}

#Preview("Loading details") {
    ScrollView { PlaceDetailsSkeleton().padding() }
}

#Preview("Loading trails") {
    List {
        TrailCard(place: SampleData.places[0], rainfall: nil, isLoading: true, error: nil)
        TrailCard(place: SampleData.places[1], rainfall: nil, isLoading: true, error: nil)
    }
    .listStyle(.plain)
}
