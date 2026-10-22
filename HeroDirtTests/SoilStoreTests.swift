import Foundation
import Testing

@testable import HeroDirt

struct SoilStoreTests {

    private func makeDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let sandy = SoilData(sandFraction: 0.8, clayFraction: 0.1)

    private actor Counter {
        var value = 0
        func increment() { value += 1 }
    }

    @Test func cachesAndPersistsAcrossInstances() async {
        let dir = makeDir()
        let calls = Counter()
        let store = SoilStore(directory: dir)
        let first = await store.soil(latitude: 37.4123, longitude: -122.2123) {
            await calls.increment()
            return sandy
        }
        #expect(first == sandy)

        let reopened = SoilStore(directory: dir)
        let second = await reopened.soil(latitude: 37.4124, longitude: -122.2124) {
            await calls.increment()
            return nil
        }
        #expect(second == sandy)
        #expect(await calls.value == 1)
    }

    @Test func failuresAreNotCached() async {
        let store = SoilStore(directory: makeDir())
        let failed = await store.soil(latitude: 1, longitude: 1) { nil }
        #expect(failed == nil)
        let retried = await store.soil(latitude: 1, longitude: 1) { sandy }
        #expect(retried == sandy)
    }

    @Test func concurrentRequestsForSameSpotAreDeduplicated() async {
        let calls = Counter()
        let store = SoilStore(directory: makeDir())
        let soil = sandy
        await withTaskGroup(of: SoilData?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await store.soil(latitude: 10, longitude: 10) {
                        await calls.increment()
                        try? await Task.sleep(for: .milliseconds(100))
                        return soil
                    }
                }
            }
        }
        #expect(await calls.value == 1)
    }

    @Test func throttlesRequestsPerWindow() async {
        let store = SoilStore(directory: makeDir(), maxRequestsPerWindow: 2, window: 0.5)
        let start = Date()
        for i in 0..<3 {
            _ = await store.soil(latitude: Double(i), longitude: 0) { sandy }
        }
        // The third request had to wait for the window to roll over.
        #expect(Date().timeIntervalSince(start) >= 0.4)
    }

    @Test func negativeCoordinatesBucketSeparately() {
        #expect(SoilStore.Key(latitude: -0.004, longitude: 0) != SoilStore.Key(latitude: 0.004, longitude: 0))
    }

    @Test func placeSoilRoundTripsThroughJSON() throws {
        let place = Place(name: "P", latitude: 1, longitude: 2, soil: sandy)
        let decoded = try JSONDecoder().decode(Place.self, from: JSONEncoder().encode(place))
        #expect(decoded.soil == sandy)
    }
}
