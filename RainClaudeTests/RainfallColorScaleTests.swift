import Testing
import SwiftUI
@testable import RainClaude

struct RainfallColorScaleTests {

    @Test func belowThresholdIsTransparent() {
        let (_, _, _, a) = RainfallColorScale.rgbaComponents(for: 0.05)
        #expect(a == 0)
    }

    @Test func atFirstVisibleStop() {
        let (r, g, b, a) = RainfallColorScale.rgbaComponents(for: 0.1)
        #expect(a > 0)
        // Light green: green component should be dominant
        #expect(g > r)
        #expect(g > b)
    }

    @Test func atMaxStop() {
        // 100+ mm should clamp to purple
        let result100 = RainfallColorScale.rgbaComponents(for: 100)
        let result200 = RainfallColorScale.rgbaComponents(for: 200)
        #expect(result100.r == result200.r)
        #expect(result100.g == result200.g)
        #expect(result100.b == result200.b)
        #expect(result100.a == result200.a)
    }

    @Test func intermediateValueInterpolates() {
        // 3.0 mm is between 1 (green) and 5 (yellow)
        let (r, g, _, a) = RainfallColorScale.rgbaComponents(for: 3.0)
        #expect(a > 0)
        // Should be between green and yellow, so both r and g should be non-trivial
        #expect(r > 0)
        #expect(g > 0)
    }

    @Test func gradientStopsCount() {
        // gradientStops excludes the clear stop
        let count = RainfallColorScale.gradientStops.count
        #expect(count == RainfallColorScale.stops.count - 1)
    }
}
