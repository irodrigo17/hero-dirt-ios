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

struct SoilCancellationTests {
    private actor Counter {
        var count = 0
        func increment() { count += 1 }
    }

    @Test func serverCooldownPausesQueuedSoilWork() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SoilStore(directory: directory)
        let counter = Counter()
        await store.pause(until: Date().addingTimeInterval(0.1))
        let task = Task {
            await store.soil(latitude: 1, longitude: 1) {
                await counter.increment()
                return SoilData(sandFraction: 0.8, clayFraction: 0.1)
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(await counter.count == 0)
        #expect(await task.value != nil)
        #expect(await counter.count == 1)
    }

    @Test func abandonedPinDoesNotConsumeAQueuedSoilRequest() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SoilStore(directory: directory, maxRequestsPerWindow: 1, window: 0.2)
        let soil = SoilData(sandFraction: 0.8, clayFraction: 0.1)
        _ = await store.soil(latitude: 0, longitude: 0) { soil }
        let counter = Counter()
        let abandoned = Task {
            await store.soil(latitude: 1, longitude: 1) { await counter.increment(); return soil }
        }
        try await Task.sleep(for: .milliseconds(20))
        abandoned.cancel()
        #expect(await abandoned.value == nil)
        try await Task.sleep(for: .milliseconds(220))
        #expect(await counter.count == 0)
        let next = await store.soil(latitude: 1, longitude: 1) { await counter.increment(); return soil }
        #expect(next == soil)
        #expect(await counter.count == 1)
    }

    @Test func cancellingOneWaiterKeepsASharedLookupAlive() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SoilStore(directory: directory)
        let soil = SoilData(sandFraction: 0.8, clayFraction: 0.1)
        let counter = Counter()
        let (started, ready) = AsyncStream<Void>.makeStream()
        let first = Task {
            await store.soil(latitude: 1, longitude: 1) {
                await counter.increment()
                ready.yield()
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return nil }
                return soil
            }
        }
        for await _ in started { break }
        let second = Task {
            await store.soil(latitude: 1, longitude: 1) { Issue.record("Shared lookup should be reused"); return nil }
        }
        try await Task.sleep(for: .milliseconds(30))
        first.cancel()
        #expect(await first.value == nil)
        #expect(await second.value == soil)
        #expect(await counter.count == 1)
    }
}
