import CoreLocation
import Foundation
import MapKit
import Testing

@testable import HeroDirt

struct SharedUtilitiesTests {
    @Test func outdoorSearchExpandsDemoAndPreservesRegion() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37, longitude: -122),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let request = OutdoorPlaceSearch.request(query: " Demo ", region: region)
        #expect(request.naturalLanguageQuery == "Soquel Demonstration State Forest")
        #expect(request.region.center.latitude == 37)
        // A server-side category filter makes MapKit reject the actual
        // uncategorized forest. Business filtering happens on the response.
        #expect(request.pointOfInterestFilter == nil)
        #expect(request.resultTypes.contains(.physicalFeature))
        #expect(OutdoorPlaceSearch.request(query: " Mount Tam ", region: nil).naturalLanguageQuery == "Mount Tam")
    }

    @Test func searchDistinguishesNoResultsFromServiceFailures() {
        #expect(OutdoorPlaceSearch.isNoResults(MKError(.placemarkNotFound)))
        #expect(!OutdoorPlaceSearch.isNoResults(MKError(.serverFailure)))
        #expect(!OutdoorPlaceSearch.isNoResults(URLError(.notConnectedToInternet)))
        #expect(!OutdoorPlaceSearch.isNoResults(NSError(domain: "Other", code: 4)))
    }

    @Test func outdoorSearchRejectsBusinessesAndKeepsNaturalFeatures() {
        func item(_ name: String, _ category: MKPointOfInterestCategory?) -> MKMapItem {
            let item = MKMapItem(location: CLLocation(latitude: 37, longitude: -122), address: nil)
            item.name = name
            item.pointOfInterestCategory = category
            return item
        }
        let items = [item("Dyson", .store), item("Forest", .park),
                     item("Restaurant", .restaurant), item("Mountain", nil), item("Trail", .hiking)]
        #expect(OutdoorPlaceSearch.results(from: items).compactMap(\.name) == ["Forest", "Mountain", "Trail"])
    }

    @Test func directionsHandOffExactCoordinateToSystemDefault() {
        let url = DrivingDirections.navigationURL(to: CLLocationCoordinate2D(latitude: 37.08, longitude: -121.91))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.scheme == "geo-navigation")
        #expect(components?.path == "/directions")
        #expect(components?.queryItems == [URLQueryItem(name: "destination", value: "37.08,-121.91")])
    }

    private static func isMainThread() -> Bool { Thread.isMainThread }

    @MainActor
    @Test func drivingLocationWorkRunsOffMainThread() async {
        let location = await DrivingLocationRequest.location {
            #expect(!Self.isMainThread())
            return CLLocation(latitude: 37, longitude: -122)
        }
        #expect(location?.coordinate.latitude == 37)
    }

    @Test func drivingLocationTimeoutCancelsPendingFix() async {
        let result = await DrivingLocationRequest.location(timeout: .milliseconds(10)) {
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return nil }
            Issue.record("Location request should have been cancelled by timeout")
            return CLLocation(latitude: 37, longitude: -122)
        }
        #expect(result == nil)
    }

    @Test func drivingLocationCancellationReturnsWithoutWaitingForTimeout() async {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            await DrivingLocationRequest.location {
                continuation.yield()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return nil }
                Issue.record("Location request should have been cancelled")
                return CLLocation(latitude: 37, longitude: -122)
            }
        }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        task.cancel()
        #expect(await task.value == nil)
    }

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

struct WeatherRequestDeadlineTests {
    @Test func slowConditionsEndInATimeoutRatherThanEndlessLoading() async {
        do {
            _ = try await WeatherRequestDeadline.run(timeout: .milliseconds(20)) {
                try await Task.sleep(for: .seconds(60))
                Issue.record("Timed-out network work should be cancelled")
                return 1
            }
            Issue.record("Expected timeout")
        } catch let error as URLError { #expect(error.code == .timedOut) }
        catch { Issue.record("Wrong error: \(error)") }
    }

    @Test func completedConditionsCancelTheDeadline() async throws {
        #expect(try await WeatherRequestDeadline.run(timeout: .seconds(60)) { 42 } == 42)
    }

    @Test func leavingAPinCancelsItsDeadlineAndRequest() async {
        let (started, ready) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await WeatherRequestDeadline.run {
                ready.yield()
                try await Task.sleep(for: .seconds(60))
                Issue.record("Cancelled pin must not finish fetching")
                return 1
            }
        }
        for await _ in started { break }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
        catch { Issue.record("Wrong error: \(error)") }
    }
}
