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

/// Placeholder that mirrors the layout of the place details cards.
struct PlaceDetailsSkeleton: View {
    var body: some View {
        VStack(spacing: 20) {
            CardContainer {
                HStack {
                    SkeletonBlock(width: 110)
                    Spacer()
                }
                HStack(spacing: 16) {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(width: 140, height: 22)
                        SkeletonBlock(height: 12)
                    }
                }
            }
            ForEach(0..<2, id: \.self) { _ in
                CardContainer {
                    HStack {
                        SkeletonBlock(width: 90)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonBlock(height: 58, cornerRadius: 8)
                        }
                    }
                }
            }
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading trail conditions")
    }
}

/// Placeholder for a saved place row's data while it loads.
struct PlaceRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SkeletonBlock(width: 96, height: 24, cornerRadius: 12)
                Spacer()
                SkeletonBlock(width: 70, height: 12)
            }
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(height: 42)
                }
            }
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
