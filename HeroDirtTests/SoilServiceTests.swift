import Foundation
import Testing

@testable import HeroDirt

// MARK: - SoilData parameter formula

struct SoilDataTests {

    @Test func sandParameters() {
        let soil = SoilData(sandFraction: 1.0, clayFraction: 0.0)
        #expect(abs(soil.fieldCapacity - 20.0) < 0.001)
        #expect(abs(soil.dryingRate - 1.5) < 0.001)
    }

    @Test func clayParameters() {
        // sand=0.1 → FC = 20 + 25×0.9 = 42.5, DR = 0.6 + 0.9×0.1 = 0.69
        let soil = SoilData(sandFraction: 0.1, clayFraction: 0.7)
        #expect(abs(soil.fieldCapacity - 42.5) < 0.001)
        #expect(abs(soil.dryingRate - 0.69) < 0.001)
    }

    @Test func loamParameters() {
        // sand=0.4 → FC = 20 + 25×0.6 = 35, DR = 0.6 + 0.9×0.4 = 0.96
        let soil = SoilData.loam
        #expect(abs(soil.fieldCapacity - 35.0) < 0.001)
        #expect(abs(soil.dryingRate - 0.96) < 0.001)
    }

    @Test func loamIsEstimated() {
        #expect(SoilData.loam.isEstimated == true)
    }

    @Test func defaultInitIsNotEstimated() {
        let soil = SoilData(sandFraction: 0.5, clayFraction: 0.2)
        #expect(soil.isEstimated == false)
    }

    // MARK: - Texture labels

    @Test func sandTextureLabel() {
        #expect(SoilData(sandFraction: 0.90, clayFraction: 0.05).textureLabel == "Sand")
    }

    @Test func loamySandTextureLabel() {
        #expect(SoilData(sandFraction: 0.75, clayFraction: 0.10).textureLabel == "Loamy Sand")
    }

    @Test func sandyLoamTextureLabel() {
        #expect(SoilData(sandFraction: 0.60, clayFraction: 0.15).textureLabel == "Sandy Loam")
    }

    @Test func clayTextureLabel() {
        #expect(SoilData(sandFraction: 0.15, clayFraction: 0.50).textureLabel == "Clay")
    }

    @Test func loamTextureLabelDefault() {
        #expect(SoilData.loam.textureLabel == "Loam")
    }
}

// MARK: - SoilService parsing

struct SoilServiceParsingTests {

    @Test func parseSandAndClay() throws {
        let json = """
            {
              "properties": {
                "layers": [
                  { "name": "sand", "depths": [{ "values": { "mean": 600.0 } }] },
                  { "name": "clay", "depths": [{ "values": { "mean": 200.0 } }] }
                ]
              }
            }
            """
        let soil = try SoilService.parseResponse(Data(json.utf8))
        #expect(abs(soil.sandFraction - 0.60) < 0.001)
        #expect(abs(soil.clayFraction - 0.20) < 0.001)
        #expect(soil.isEstimated == false)
    }

    @Test func missingLayerFallsBackToLoam() throws {
        let json = """
            { "properties": { "layers": [] } }
            """
        let soil = try SoilService.parseResponse(Data(json.utf8))
        #expect(soil.sandFraction == SoilData.loam.sandFraction)
        #expect(soil.isEstimated == true)
    }

    @Test func clampsFractionsTo1() throws {
        let json = """
            {
              "properties": {
                "layers": [
                  { "name": "sand", "depths": [{ "values": { "mean": 1500.0 } }] },
                  { "name": "clay", "depths": [{ "values": { "mean": 900.0 } }] }
                ]
              }
            }
            """
        let soil = try SoilService.parseResponse(Data(json.utf8))
        #expect(soil.sandFraction <= 1.0)
        #expect(soil.clayFraction <= 1.0)
    }
}

// MARK: - Moisture balance algorithm

struct MoistureBalanceTests {

    private func makeSummary(days: [(rain: Double, et0: Double)]) -> RainfallSummary {
        let today = Date()
        let daily = days.enumerated().map { i, d in
            DailyWeatherData(
                date: Calendar.current.date(byAdding: .day, value: -i, to: today)!,
                amount: d.rain,
                et0: d.et0
            )
        }
        return RainfallSummary(daily: daily)
    }

    // Legacy fallback when all ET0 values are zero
    @Test func noET0FallsBackToLegacy() {
        let summary = makeSummary(days: [(rain: 25.4, et0: 0.0)])
        let result = summary.dirtConditionResult()
        #expect(result.condition == .wet)
        #expect(result.moistureIndex == nil)
        #expect(result.soil == nil)
    }

    // New algorithm provides moisture index and soil data
    @Test func withET0ProvidesFullResult() {
        let summary = makeSummary(days: [(rain: 25.4, et0: 5.0)])
        let result = summary.dirtConditionResult()
        #expect(result.moistureIndex != nil)
        #expect(result.soil != nil)
        #expect(result.recentET0 != nil)
    }

    // 30 days with no rain and high ET → very dry
    @Test func zeroRainHighET0IsVeryDry() {
        let days = Array(repeating: (rain: 0.0, et0: 8.0), count: 30)
        let summary = makeSummary(days: days)
        let condition = summary.dirtCondition()
        #expect(condition == .dry || condition == .veryDry)
    }

    // Saturation: enormous rain → very wet or wet
    @Test func heavyRainIsVeryWet() {
        var days = Array(repeating: (rain: 0.0, et0: 5.0), count: 29)
        days.insert((rain: 200.0, et0: 5.0), at: 0)
        let summary = makeSummary(days: days)
        let condition = summary.dirtCondition()
        #expect(condition == .veryWet || condition == .wet)
    }

    // Sand dries faster than clay given the same rain history
    @Test func sandDriesFasterThanClay() {
        var days = Array(repeating: (rain: 0.0, et0: 5.0), count: 30)
        days[3] = (rain: 25.4, et0: 5.0)
        let summary = makeSummary(days: days)

        let sandCondition = summary.dirtCondition(soil: SoilData(sandFraction: 0.9, clayFraction: 0.05))
        let clayCondition = summary.dirtCondition(soil: SoilData(sandFraction: 0.1, clayFraction: 0.7))

        let order: [DirtCondition] = [.veryWet, .wet, .heroDirt, .dry, .veryDry]
        let sandIdx = order.firstIndex(of: sandCondition)!
        let clayIdx = order.firstIndex(of: clayCondition)!
        #expect(sandIdx >= clayIdx)
    }

    // Loam + 1 inch rain 2 days ago + ET0=5mm → heroDirt or drier
    @Test func loamOneInchRainHeroDirtByDay2() {
        var days = Array(repeating: (rain: 0.0, et0: 5.0), count: 30)
        days[2] = (rain: 25.4, et0: 5.0)
        let summary = makeSummary(days: days)
        let condition = summary.dirtCondition(soil: .loam)
        let order: [DirtCondition] = [.veryWet, .wet, .heroDirt, .dry, .veryDry]
        let idx = order.firstIndex(of: condition)!
        #expect(idx >= 2)
    }

    // Estimated soil is used when nil is passed
    @Test func nilSoilUsesEstimatedLoam() {
        let days = Array(repeating: (rain: 5.0, et0: 4.0), count: 10)
        let summary = makeSummary(days: days)
        let result = summary.dirtConditionResult(soil: nil)
        #expect(result.soil?.isEstimated == true)
    }
}
