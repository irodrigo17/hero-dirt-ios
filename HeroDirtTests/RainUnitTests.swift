import Foundation
import Testing

@testable import HeroDirt

struct RainUnitTests {

    @Test func millimetersMatchLegacyFormatting() {
        #expect(RainUnit.millimeters.format(5.5) == "5.5")
        #expect(RainUnit.millimeters.format(25.4) == "25")
        #expect(RainUnit.millimeters.formatWithUnit(4.2) == "4.2 mm")
    }

    @Test func inchesFormatting() {
        #expect(RainUnit.inches.format(0) == "0")
        #expect(RainUnit.inches.format(0.1) == "<0.01")
        #expect(RainUnit.inches.format(18.0) == "0.71")
        #expect(RainUnit.inches.format(50.8) == "2.0")
        #expect(RainUnit.inches.formatWithUnit(25.4) == "1.0 in")
    }

    @Test func automaticFollowsMeasurementSystem() {
        #expect(RainUnitPreference.automatic.resolved(locale: Locale(identifier: "en_US")) == .inches)
        #expect(RainUnitPreference.automatic.resolved(locale: Locale(identifier: "es_UY")) == .millimeters)
        #expect(RainUnitPreference.millimeters.resolved(locale: Locale(identifier: "en_US")) == .millimeters)
        #expect(RainUnitPreference.inches.resolved(locale: Locale(identifier: "en_GB")) == .inches)
    }

    @Test func legendHasLabelsForBothUnits() {
        for stop in RainfallColorScale.stops {
            #expect(!stop.label(for: .millimeters).isEmpty)
            #expect(!stop.label(for: .inches).isEmpty)
        }
    }
}
