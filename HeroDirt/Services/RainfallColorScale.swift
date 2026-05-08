import Foundation
import UIKit

enum RainfallColorScale {

    struct Stop {
        let threshold: Double
        let color: UIColor
        let label: String
    }

    static let stops: [Stop] = [
        Stop(threshold: 0, color: .clear, label: "0"),
        Stop(threshold: 0.1, color: UIColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1), label: "0.1"),
        Stop(threshold: 1, color: .systemGreen, label: "1"),
        Stop(threshold: 5, color: .systemYellow, label: "5"),
        Stop(threshold: 10, color: .systemOrange, label: "10"),
        Stop(threshold: 25, color: .systemRed, label: "25"),
        Stop(threshold: 50, color: UIColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1), label: "50"),
        Stop(threshold: 100, color: .systemPurple, label: "100+"),
    ]

    private struct StopRGBA {
        let threshold: Double
        let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    }

    private static let stopRGBAs: [StopRGBA] = {
        stops.map { stop in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            stop.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return StopRGBA(threshold: stop.threshold, r: r, g: g, b: b, a: a)
        }
    }()

    static func rgbaComponents(for mm: Double) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        if mm < 0.1 { return (0, 0, 0, 0) }
        let visible = Array(stopRGBAs.dropFirst())
        precondition(visible.count >= 2, "RainfallColorScale needs at least 2 visible stops")
        var lower = visible.first!
        var upper = visible.last!
        for stop in visible {
            if mm < stop.threshold { upper = stop; break }
            lower = stop
        }
        if mm >= upper.threshold { return (upper.r, upper.g, upper.b, upper.a) }
        let t = CGFloat((mm - lower.threshold) / (upper.threshold - lower.threshold))
        return (
            lower.r + (upper.r - lower.r) * t,
            lower.g + (upper.g - lower.g) * t,
            lower.b + (upper.b - lower.b) * t,
            lower.a + (upper.a - lower.a) * t
        )
    }

    static func color(for mm: Double) -> UIColor {
        let (r, g, b, a) = rgbaComponents(for: mm)
        if a == 0 { return .clear }
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
