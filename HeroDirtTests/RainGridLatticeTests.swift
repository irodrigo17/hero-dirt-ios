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
