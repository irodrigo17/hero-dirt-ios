import SwiftUI
import UIKit

enum RainfallColorScale {

    struct Stop {
        let threshold: Double  // mm
        let color: Color
        let label: String
        var inchLabel: String = ""

        func label(for unit: RainUnit) -> String {
            unit == .inches ? inchLabel : label
        }
    }

    static let stops: [Stop] = [
        Stop(threshold: 0, color: .clear, label: "0", inchLabel: "0"),
        Stop(
            threshold: 0.1,
            color: Color(.sRGB, red: 0.60, green: 0.83, blue: 0.61, opacity: 1),
            label: "0.1",
            inchLabel: "0"
        ),
        Stop(threshold: 1, color: Color(.sRGB, red: 0.28, green: 0.69, blue: 0.39, opacity: 1), label: "1", inchLabel: ".04"),
        Stop(threshold: 5, color: Color(.sRGB, red: 0.89, green: 0.75, blue: 0.20, opacity: 1), label: "5", inchLabel: ".2"),
        Stop(threshold: 10, color: Color(.sRGB, red: 0.88, green: 0.56, blue: 0.15, opacity: 1), label: "10", inchLabel: ".4"),
        Stop(threshold: 25, color: Color(.sRGB, red: 0.85, green: 0.29, blue: 0.25, opacity: 1), label: "25", inchLabel: "1"),
        Stop(
            threshold: 50,
            color: Color(.sRGB, red: 0.69, green: 0.30, blue: 0.69, opacity: 1),
            label: "50",
            inchLabel: "2"
        ),
        Stop(threshold: 100, color: Color(.sRGB, red: 0.56, green: 0.34, blue: 0.72, opacity: 1), label: "100+", inchLabel: "4+"),
    ]

    // Pre-computed RGBA components for each stop (avoids repeated UIColor conversions)
    private struct StopRGBA {
        let threshold: Double
        let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    }

    private static let stopRGBAs: [StopRGBA] = {
        stops.map { stop in
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            UIColor(stop.color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return StopRGBA(threshold: stop.threshold, r: r, g: g, b: b, a: a)
        }
    }()

    /// Returns raw RGBA components for a given rainfall amount (efficient for bitmap rendering)
    static func rgbaComponents(for mm: Double) -> (
        r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    ) {
        if mm < 0.1 {
            return (0, 0, 0, 0)
        }

        let visible = Array(stopRGBAs.dropFirst())
        precondition(
            visible.count >= 2,
            "RainfallColorScale needs at least 2 visible stops"
        )

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

        let t = CGFloat(
            (mm - lower.threshold) / (upper.threshold - lower.threshold)
        )
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
        return Color(
            .sRGB,
            red: Double(r),
            green: Double(g),
            blue: Double(b),
            opacity: Double(a)
        )
    }

    /// Gradient stops for legend display (excludes the clear stop)
    static var gradientStops: [Gradient.Stop] {
        let visible = Array(stops.dropFirst())
        guard let minT = visible.first?.threshold,
            let maxT = visible.last?.threshold,
            maxT > minT
        else { return [] }
        return visible.map { stop in
            let location = (stop.threshold - minT) / (maxT - minT)
            return Gradient.Stop(color: stop.color, location: location)
        }
    }
}
