import Testing
import CoreLocation
@testable import RainClaude

struct RainfallOverlayTests {

    private func makeSummary(last1Day: Double = 1, last2Days: Double = 2,
                             last3Days: Double = 3, last7Days: Double = 7) -> RainfallSummary {
        RainfallSummary(last1Day: last1Day, last2Days: last2Days,
                        last3Days: last3Days, last7Days: last7Days,
                        daysSinceLastRain: 0)
    }

    // MARK: - RainfallTimeframe

    @Test func timeframeAmountReturnsCorrectField() {
        let summary = makeSummary()
        #expect(RainfallTimeframe.oneDay.amount(from: summary) == 1)
        #expect(RainfallTimeframe.twoDays.amount(from: summary) == 2)
        #expect(RainfallTimeframe.threeDays.amount(from: summary) == 3)
        #expect(RainfallTimeframe.sevenDays.amount(from: summary) == 7)
    }

    @Test func timeframeAllCasesCount() {
        #expect(RainfallTimeframe.allCases.count == 4)
    }

    // MARK: - RainfallCell

    @Test func cellPolygonCorners() {
        let cell = RainfallCell(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 10.0, longitude: 20.0),
            latDelta: 2.0,
            lonDelta: 4.0,
            summary: makeSummary()
        )

        let poly = cell.polygon
        #expect(poly.count == 4)

        // Bottom-left
        #expect(poly[0].latitude == 9.0)
        #expect(poly[0].longitude == 18.0)
        // Bottom-right
        #expect(poly[1].latitude == 9.0)
        #expect(poly[1].longitude == 22.0)
        // Top-right
        #expect(poly[2].latitude == 11.0)
        #expect(poly[2].longitude == 22.0)
        // Top-left
        #expect(poly[3].latitude == 11.0)
        #expect(poly[3].longitude == 18.0)
    }
}
