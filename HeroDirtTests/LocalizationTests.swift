import Foundation
import Testing

@testable import HeroDirt

struct LocalizationTests {
    @Test(arguments: ["es", "fr", "de", "pt-BR", "ja"])
    func translatedResourcesAreBundled(_ language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        for key in ["My Trails", "Trail Conditions", "Share Trail", "Rain Calendar", "What's the dirt like?", "You're offline."] {
            let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            #expect(value != key, "Missing translation for \(language): \(key)")
            #expect(!value.isEmpty)
        }
        let permission = bundle.localizedString(forKey: "NSLocationWhenInUseUsageDescription", value: nil, table: "InfoPlist")
        #expect(permission != "NSLocationWhenInUseUsageDescription")
        #expect(permission.count > 30)
    }

    @Test(arguments: ["es", "fr", "de", "pt-BR", "ja"])
    func interpolatedForecastsAndPluralsResolve(_ language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let locale = Locale(identifier: language)
        let day = "TEST_DAY"
        let outlook = String(localized: "Hero dirt by \(day)", bundle: bundle, locale: locale)
        #expect(outlook.contains(day))
        #expect(!outlook.contains("%@"))
        #expect(!outlook.hasPrefix("Hero dirt by"))
        let count = 3
        let ago = String(localized: "\(count) days ago", bundle: bundle, locale: locale)
        #expect(ago.contains("3"))
        #expect(!ago.contains("%lld"))
        #expect(ago != "3 days ago")
    }

    @Test func rainfallUsesRegionalDecimalSeparators() {
        #expect(RainUnit.millimeters.format(4.2, locale: Locale(identifier: "de_DE")) == "4,2")
        #expect(RainUnit.inches.format(0.1, locale: Locale(identifier: "fr_FR")) == "<0,01")
        #expect(RainUnit.millimeters.format(4.2, locale: Locale(identifier: "ja_JP")) == "4.2")
    }

    @Test func localizationDoesNotChangePersistedSoilValues() throws {
        let override = SoilOverride(textureClass: .sandyLoam, exposure: .partial)
        let data = try JSONEncoder().encode(override)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json["textureClass"] == "Sandy Loam")
        #expect(json["exposure"] == "Partial")
        #expect(try JSONDecoder().decode(SoilOverride.self, from: data) == override)
    }
}
