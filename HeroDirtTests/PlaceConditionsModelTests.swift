import Foundation
import MapKit
import Testing
import UIKit

@testable import HeroDirt

@MainActor
struct PlaceConditionsModelTests {

    @Test func loadsRainForEveryPlace() async {
        let model = PlaceConditionsModel()
        await model.load(SampleData.places, weather: FakeWeatherProvider())
        #expect(model.rainfall.count == SampleData.places.count)
        #expect(model.loading.isEmpty)
        #expect(model.errors.isEmpty)
    }

    @Test func failuresBecomeFriendlyErrors() async {
        let model = PlaceConditionsModel()
        let weather = FakeWeatherProvider(failure: URLError(.notConnectedToInternet))
        await model.load(SampleData.places, weather: weather)
        #expect(model.rainfall.isEmpty)
        #expect(model.errors.values.allSatisfy { $0.hasPrefix("You're offline.") })
        #expect(model.loading.isEmpty)
    }

    @Test func cancelledLoadIsRetriedNotReportedAsError() async {
        let model = PlaceConditionsModel()
        let slow = FakeWeatherProvider(delay: .seconds(5))
        let task = Task { await model.load(SampleData.places, weather: slow) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        #expect(model.errors.isEmpty)

        await model.load(SampleData.places, weather: FakeWeatherProvider())
        #expect(model.rainfall.count == SampleData.places.count)
        #expect(model.loading.isEmpty)
    }

    @Test func backfillsMissingSoilIntoTheStore() async throws {
        let place = Place(name: "No soil", latitude: 1, longitude: 2)
        let store = SampleData.placeStore([place])
        let model = PlaceConditionsModel()
        model.backfillSoil(store.places, soil: FakeSoilProvider(), store: store)
        for _ in 0..<50 where store.places.first?.soil == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.places.first?.soil == SampleData.loam)
    }

    @Test func rateLimitMessage() {
        let message = PlaceConditionsModel.friendlyMessage(for: WeatherService.WeatherError.httpError(statusCode: 429))
        #expect(message.contains("Too many requests"))
    }
}

@MainActor
struct RainfallGridServiceTests {

    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.4, longitude: -122.2),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.3)
    )

    @Test(.timeLimit(.minutes(2))) func rendersOverlayFromFetchedGrid() async {
        let service = RainfallGridService(diskCache: RainGridDiskCache(directory: nil)) { points, _ in points.map { _ in SampleData.muddy } }
        await service.load(region: region, pastDays: 3)
        #expect(service.overlay != nil)
        #expect(service.errorMessage == nil)
        #expect(!service.isLoading)
    }

    @Test(.timeLimit(.minutes(1))) func loadingWaitsForRenderingAndCancellationDiscardsLateImages() async {
        let (started, ready) = AsyncStream<Void>.makeStream()
        let (release, unblock) = AsyncStream<Void>.makeStream()
        let service = RainfallGridService(diskCache: .init(directory: nil), renderer: { _ in
            ready.yield()
            for await _ in release { break }
            return UIImage()
        }) { points, _ in points.map { _ in SampleData.muddy } }
        let load = Task { await service.load(region: region, pastDays: 3) }
        for await _ in started { break }
        #expect(service.isLoading)
        #expect(service.overlay == nil)
        service.cancelUpdate()
        unblock.yield()
        await load.value
        #expect(!service.isLoading)
        #expect(service.overlay == nil)
    }

    @Test(.timeLimit(.minutes(1))) func completedLoadPublishesImageBeforeReturning() async {
        let (started, ready) = AsyncStream<Void>.makeStream()
        let (release, unblock) = AsyncStream<Void>.makeStream()
        let service = RainfallGridService(diskCache: .init(directory: nil), renderer: { _ in
            ready.yield()
            for await _ in release { break }
            return UIImage()
        }) { points, _ in points.map { _ in SampleData.muddy } }
        let load = Task { await service.load(region: region, pastDays: 3) }
        for await _ in started { break }
        #expect(service.isLoading)
        #expect(service.overlay == nil)
        unblock.yield()
        await load.value
        #expect(!service.isLoading)
        #expect(service.overlay != nil)
    }

    @Test func surfacesFetchErrors() async throws {
        let service = RainfallGridService(diskCache: RainGridDiskCache(directory: nil)) { _, _ in throw WeatherService.WeatherError.httpError(statusCode: 429) }
        await service.load(region: region, pastDays: 3)
        #expect(service.errorMessage?.contains("Too many requests") == true)
    }
}
