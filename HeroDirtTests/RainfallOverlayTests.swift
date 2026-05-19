import Testing

@testable import HeroDirt

struct RainfallOverlayTests {

    private func makeSummary(
        last1Day: Double = 1,
        last2Days: Double = 2,
        last3Days: Double = 3,
        last7Days: Double = 7
    ) -> RainfallSummary {
        RainfallSummary(
            last1Day: last1Day,
            last2Days: last2Days,
            last3Days: last3Days,
            last7Days: last7Days,
            daysSinceLastRain: 0
        )
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

    @Test func timeframeLabels() {
        #expect(RainfallTimeframe.oneDay.label == "1 Day")
        #expect(RainfallTimeframe.twoDays.label == "2 Days")
        #expect(RainfallTimeframe.threeDays.label == "3 Days")
        #expect(RainfallTimeframe.sevenDays.label == "7 Days")
    }

    @Test func timeframeIDs() {
        #expect(RainfallTimeframe.oneDay.id == "1d")
        #expect(RainfallTimeframe.twoDays.id == "2d")
        #expect(RainfallTimeframe.threeDays.id == "3d")
        #expect(RainfallTimeframe.sevenDays.id == "7d")
    }

}
