import Foundation
import Testing

@testable import HeroDirt

struct SharedUtilitiesTests {

    @MainActor
    @Test func feedbackEmailUsesRequestedRecipient() throws {
        let components = try #require(URLComponents(url: AboutView.feedbackEmailURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "irodrigo17@gmail.com")
        #expect(components.queryItems?.first(where: { $0.name == "subject" })?.value == "Hero Dirt Feedback")
        #expect(components.queryItems?.first(where: { $0.name == "body" })?.value?.contains(AppInfo.diagnosticsSummary) == true)
    }

    // MARK: - Double.formatMillimeters

    @Test func formatSingleDigit() {
        #expect(Double(5.5).formatMillimeters() == "5.5")
        #expect(Double(0.1).formatMillimeters() == "0.1")
        #expect(Double(9.9).formatMillimeters() == "9.9")
    }

    @Test func formatDoubleDigitRounds() {
        #expect(Double(10.5).formatMillimeters() == "10")
        #expect(Double(25.4).formatMillimeters() == "25")
        #expect(Double(100.0).formatMillimeters() == "100")
    }

    @Test func formatZero() {
        #expect(Double(0.0).formatMillimeters() == "0.0")
    }

    // MARK: - Corner radius constants

    @Test func cornerRadiusValues() {
        #expect(CGFloat.cornerSmall == 6)
        #expect(CGFloat.cornerMedium == 12)
        #expect(CGFloat.cornerLarge == 16)
    }

    @Test func cornerRadiusOrdering() {
        #expect(CGFloat.cornerSmall < CGFloat.cornerMedium)
        #expect(CGFloat.cornerMedium < CGFloat.cornerLarge)
    }
}
