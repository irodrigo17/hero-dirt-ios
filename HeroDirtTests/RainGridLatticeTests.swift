import MapKit
import Testing

@testable import HeroDirt

struct RainGridLatticeTests {

    private func region(_ lat: Double, _ lon: Double, span: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 0.6)
        )
    }

    @Test func smallPanReusesTheSameCells() {
        let a = RainGridLattice(region: region(37.40, -122.20, span: 1.0))
        let b = RainGridLattice(region: region(37.43, -122.17, span: 1.0))
        #expect(a.step == b.step)
        // Cell centers are on the same global lattice, so overlapping cells
        // have identical coordinates (and cache keys).
        let shared = Set(a.rowRange).intersection(Set(b.rowRange))
        #expect(shared.count >= a.rows - 2)
        let row = shared.first!
        #expect(a.center(row: row, col: a.colRange.lowerBound + 1)
            == b.center(row: row, col: a.colRange.lowerBound + 1))
    }

    @Test func stepComesFromFixedLadder() {
        for span in [0.3, 1.0, 2.5, 8.0, 40.0] {
            let lattice = RainGridLattice(region: region(10, 10, span: span))
            #expect(RainGridLattice.steps.contains(lattice.step))
        }
    }

    @Test func gridCoversVisibleRegionAndStaysSmall() {
        let r = region(-33.9, 151.2, span: 1.2)
        let lattice = RainGridLattice(region: r)
        let b = lattice.bounds
        #expect(b.minLat <= r.center.latitude - r.span.latitudeDelta / 2)
        #expect(b.maxLat >= r.center.latitude + r.span.latitudeDelta / 2)
        #expect(b.minLon <= r.center.longitude - r.span.longitudeDelta / 2)
        #expect(b.maxLon >= r.center.longitude + r.span.longitudeDelta / 2)
        #expect(lattice.rows * lattice.cols <= 400)
    }

    @Test func negativeCoordinatesUseFloor() {
        // -0.01 must not share a cell with +0.01.
        let step = 0.05
        #expect(Int(floor(-0.01 / step)) != Int(floor(0.01 / step)))
    }

    @Test func renderProducesImageOfExpectedSize() {
        let grid: [[Double?]] = [[0, 5, nil], [10, 25, 50]]
        let image = RainfallGridService.renderImage(values: grid)
        #expect(image?.cgImage?.width == 24)
        #expect(image?.cgImage?.height == 16)
    }
}

@MainActor
struct RainMapBudgetTests {
    private actor Recorder {
        var batches: [Int] = []
        var days: [Int] = []
        var requests: [[String]] = []
        var failAfterFirst = false
        func fetch(_ points: [(lat: Double, lon: Double)], days: Int) throws -> [RainfallSummary?] {
            requests.append(points.map { "\($0.lat),\($0.lon)" })
            let count = points.count
            if failAfterFirst && !batches.isEmpty { throw WeatherService.WeatherError.httpError(statusCode: 503) }
            batches.append(count)
            self.days.append(days)
            return Array(repeating: SampleData.muddy, count: count)
        }
        func failLater() { failAfterFirst = true }
    }

    @Test func continentalViewMakesNoRequestsAndLocalGridIsBounded() async {
        let recorder = Recorder()
        let service = RainfallGridService { points, days in try await recorder.fetch(points, days: days) }
        let usa = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39, longitude: -98),
                                     span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 65))
        await service.load(region: usa, pastDays: 3)
        #expect(await recorder.batches.isEmpty)
        #expect(service.overlay == nil)
        #expect(service.errorMessage != nil)
        for span in [0.1, 1, 5, 20, 65, 180, 360] as [Double] {
            let region = MKCoordinateRegion(center: .init(latitude: 0, longitude: 0),
                                            span: .init(latitudeDelta: min(180, span), longitudeDelta: span))
            let grid = RainGridLattice(region: region)
            #expect(grid.rows * grid.cols <= 81)
            for row in grid.rowRange {
                #expect(abs(grid.center(row: row, col: grid.colRange.lowerBound).lat) <= 90)
            }
        }
    }

    @Test func rapidBrowsingDoesNotStartRequestsBeforeSettling() async throws {
        let recorder = Recorder()
        let service = RainfallGridService { points, days in try await recorder.fetch(points, days: days) }
        let region = MKCoordinateRegion(center: .init(latitude: 37.4, longitude: -122.2),
                                       span: .init(latitudeDelta: 0.5, longitudeDelta: 0.3))
        for _ in 0..<5 { service.updateRegion(region) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(await recorder.requests.isEmpty)
        service.cancelUpdate()
        try await Task.sleep(for: .milliseconds(950))
        #expect(await recorder.requests.isEmpty)
        #expect(!service.isLoading)
    }

    @Test func timeframesReuseCacheAndCompletedBatchesSurviveLaterFailure() async throws {
        let recorder = Recorder()
        let service = RainfallGridService { points, days in try await recorder.fetch(points, days: days) }
        let region = MKCoordinateRegion(center: .init(latitude: 37.4, longitude: -122.2),
                                       span: .init(latitudeDelta: 0.5, longitudeDelta: 0.3))
        await recorder.failLater()
        await service.load(region: region, pastDays: 1)
        #expect(await recorder.batches == [16])
        await service.load(region: region, pastDays: 7)
        // The second attempt still fails, but does not re-request the first
        // successful batch. Allow a later retry to complete for reuse checks.
        #expect(await recorder.batches == [16])
        let requests = await recorder.requests
        #expect(requests.count == 3)
        #expect(requests[0] != requests[1])
        #expect(requests[1] == requests[2])
        let successful = Recorder()
        let cached = RainfallGridService { points, days in try await successful.fetch(points, days: days) }
        await cached.load(region: region, pastDays: 1)
        let calls = await successful.batches.count
        #expect(await successful.batches.allSatisfy { $0 <= 16 })
        #expect(await successful.days.allSatisfy { $0 == 7 })
        await cached.load(region: region, pastDays: 7)
        #expect(await successful.batches.count == calls)
    }
}
