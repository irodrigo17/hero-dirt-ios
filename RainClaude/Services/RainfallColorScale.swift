import SwiftUI
import UIKit

enum RainfallColorScale {

    struct Stop {
        let threshold: Double // mm
        let color: Color
        let label: String
    }

    static let stops: [Stop] = [
        Stop(threshold: 0, color: .clear, label: "0"),
        Stop(threshold: 0.1, color: Color(.sRGB, red: 0.6, green: 0.9, blue: 0.6, opacity: 1), label: "0.1"),
        Stop(threshold: 1, color: .green, label: "1"),
        Stop(threshold: 5, color: .yellow, label: "5"),
        Stop(threshold: 10, color: .orange, label: "10"),
        Stop(threshold: 25, color: .red, label: "25"),
        Stop(threshold: 50, color: Color(.sRGB, red: 0.8, green: 0.2, blue: 0.8, opacity: 1), label: "50"),
        Stop(threshold: 100, color: .purple, label: "100+"),
    ]

    // Pre-computed RGBA components for each stop (avoids repeated UIColor conversions)
    private struct StopRGBA {
        let threshold: Double
        let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    }

    private static let stopRGBAs: [StopRGBA] = {
        stops.map { stop in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(stop.color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return StopRGBA(threshold: stop.threshold, r: r, g: g, b: b, a: a)
        }
    }()

    /// Returns raw RGBA components for a given rainfall amount (efficient for bitmap rendering)
    static func rgbaComponents(for mm: Double) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        if mm < 0.1 {
            return (0, 0, 0, 0)
        }

        let visible = stopRGBAs.dropFirst() // skip clear stop
        var lower = visible.first!
        var upper = visible.last!

        for stop in visible {
            if mm < stop.threshold {
                upper = stop
                break
            }
            lower = stop
        }

        if mm >= upper.threshold {
            return (upper.r, upper.g, upper.b, upper.a)
        }

        let t = CGFloat((mm - lower.threshold) / (upper.threshold - lower.threshold))
        return (
            lower.r + (upper.r - lower.r) * t,
            lower.g + (upper.g - lower.g) * t,
            lower.b + (upper.b - lower.b) * t,
            lower.a + (upper.a - lower.a) * t
        )
    }

    static func color(for mm: Double) -> Color {
        let (r, g, b, a) = rgbaComponents(for: mm)
        if a == 0 { return .clear }
        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    /// Gradient stops for legend display (excludes the clear stop)
    static var gradientStops: [Gradient.Stop] {
        let visible = Array(stops.dropFirst())
        guard let minT = visible.first?.threshold,
              let maxT = visible.last?.threshold,
              maxT > minT else { return [] }
        return visible.map { stop in
            let location = (stop.threshold - minT) / (maxT - minT)
            return Gradient.Stop(color: stop.color, location: location)
        }
    }
}
