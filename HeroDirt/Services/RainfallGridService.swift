import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import MapKit
import UIKit
import Observation
import os

struct RainfallGridBounds: Equatable, Sendable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    var topLeft: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: maxLat, longitude: minLon)
    }
    var bottomRight: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: minLat, longitude: maxLon)
    }
}

/// A rendered rain map image and where it goes on the map.
struct RainfallOverlayImage: Equatable {
    let image: UIImage
    let bounds: RainfallGridBounds
}

/// Fixed geographic lattice the rain map samples. Points sit at cell centers
/// `(index + 0.5) * step`, so the same place always maps to the same cell:
/// panning reuses cached cells instead of fetching a fresh, shifted grid.
struct RainGridLattice: Equatable, Sendable {
    /// Allowed cell sizes in degrees, finest first. A small fixed set keeps
    /// cache hits high across zoom levels.
    static let steps: [Double] = [0.05, 0.1, 0.2, 0.5, 1, 2, 5]
    /// Target number of cells across the longer side of the visible region.
    static let targetCells = 12.0

    let step: Double
    let rowRange: ClosedRange<Int>  // latitude indices, south → north
    let colRange: ClosedRange<Int>  // longitude indices, west → east

    init(region: MKCoordinateRegion, padding: Int = 1) {
        let longest = max(region.span.latitudeDelta, region.span.longitudeDelta)
        let ideal = longest / Self.targetCells
        let step = Self.steps.first { $0 >= ideal } ?? Self.steps.last!
        self.step = step
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        rowRange = (Int(floor(minLat / step)) - padding)...(Int(floor(maxLat / step)) + padding)
        colRange = (Int(floor(minLon / step)) - padding)...(Int(floor(maxLon / step)) + padding)
    }

    var rows: Int { rowRange.count }
    var cols: Int { colRange.count }

    func center(row: Int, col: Int) -> (lat: Double, lon: Double) {
        ((Double(row) + 0.5) * step, (Double(col) + 0.5) * step)
    }

    var bounds: RainfallGridBounds {
        RainfallGridBounds(
            minLat: Double(rowRange.lowerBound) * step,
            maxLat: Double(rowRange.upperBound + 1) * step,
            minLon: Double(colRange.lowerBound) * step,
            maxLon: Double(colRange.upperBound + 1) * step
        )
    }
}

@MainActor
@Observable
final class RainfallGridService {

    /// Points of Interest intervals for Instruments (grid fetches and renders).
    @ObservationIgnored nonisolated private static let signposter = OSSignposter(
        subsystem: "com.herodirt.app",
        category: .pointsOfInterest
    )
    nonisolated private static let logger = Logger(subsystem: "com.herodirt.app", category: "RainMap")

    // MARK: - Public state

    private(set) var isLoading = false
    private(set) var overlay: RainfallOverlayImage?
    /// Set when the last fetch failed (e.g. rate limited); cleared on success.
    private(set) var errorMessage: String?

    @ObservationIgnored var timeframe: RainfallTimeframe = .threeDays

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let step: Double
        let row: Int
        let col: Int
        let pastDays: Int
    }

    private struct CacheEntry {
        let amount: Double
        let timestamp: Date
    }

    @ObservationIgnored private var cache: [CacheKey: CacheEntry] = [:]
    @ObservationIgnored private let cacheTTL: TimeInterval = 60 * 60
    @ObservationIgnored private let maxCacheEntries = 20_000

    // MARK: - Tasks

    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var lastRegion: MKCoordinateRegion?
    @ObservationIgnored private var renderGeneration = 0

    @ObservationIgnored private let gridSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Fetches rain for many points; injectable for tests.
    typealias BatchFetcher = @Sendable (_ points: [(lat: Double, lon: Double)], _ pastDays: Int) async throws -> [RainfallSummary?]
    @ObservationIgnored private let fetchBatch: BatchFetcher

    init(fetchBatch: BatchFetcher? = nil) {
        let session = gridSession
        self.fetchBatch = fetchBatch ?? { points, pastDays in
            try await WeatherService.fetchRainfallBatch(points: points, pastDays: pastDays, session: session)
        }
    }

    // MARK: - Public API

    func updateRegion(_ region: MKCoordinateRegion) {
        lastRegion = region
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            await self.load(region: region, pastDays: self.timeframe.pastDays)
        }
    }

    func cancelUpdate() {
        updateTask?.cancel()
        updateTask = nil
    }

    func refetch() {
        guard let region = lastRegion else { return }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }
            await self.load(region: region, pastDays: self.timeframe.pastDays)
        }
    }

    // MARK: - Loading

    private func load(region: MKCoordinateRegion, pastDays: Int) async {
        let lattice = RainGridLattice(region: region)
        pruneCache()

        var missing: [(row: Int, col: Int)] = []
        for row in lattice.rowRange {
            for col in lattice.colRange
            where cache[key(lattice, row, col, pastDays)] == nil {
                missing.append((row, col))
            }
        }

        Self.logger.info("rain grid: \(lattice.rows * lattice.cols) cells at \(lattice.step)°, fetching \(missing.count)")
        if !missing.isEmpty {
            isLoading = true
            defer { isLoading = false }
            let state = Self.signposter.beginInterval("Fetch rain grid", "\(missing.count) points")
            defer { Self.signposter.endInterval("Fetch rain grid", state) }
            do {
                let points = missing.map { lattice.center(row: $0.row, col: $0.col) }
                let summaries = try await fetchBatch(
                    points.map { (lat: $0.lat, lon: $0.lon) },
                    pastDays
                )
                let now = Date()
                for (i, cell) in missing.enumerated() {
                    guard let summary = summaries[i] else { continue }
                    let amount = Self.amount(summary, pastDays: pastDays)
                    cache[key(lattice, cell.row, cell.col, pastDays)] = CacheEntry(amount: amount, timestamp: now)
                }
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("rain grid fetch failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = (error as? WeatherService.WeatherError)?.errorDescription
                    ?? String(localized: "Couldn't load rain data. Check your connection.")
                // Fall through: render whatever cells are cached.
            }
        }

        guard !Task.isCancelled else { return }

        var values = [[Double?]](
            repeating: [Double?](repeating: nil, count: lattice.cols),
            count: lattice.rows
        )
        for (r, row) in lattice.rowRange.enumerated() {
            for (c, col) in lattice.colRange.enumerated() {
                values[r][c] = cache[key(lattice, row, col, pastDays)]?.amount
            }
        }
        render(values: values, bounds: lattice.bounds)
    }

    private func key(_ lattice: RainGridLattice, _ row: Int, _ col: Int, _ pastDays: Int) -> CacheKey {
        CacheKey(step: lattice.step, row: row, col: col, pastDays: pastDays)
    }

    private static func amount(_ summary: RainfallSummary, pastDays: Int) -> Double {
        switch pastDays {
        case 1: return summary.last1Day
        case 2: return summary.last2Days
        case 3: return summary.last3Days
        default: return summary.last7Days
        }
    }

    private func pruneCache() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
        if cache.count > maxCacheEntries {
            let sorted = cache.sorted { $0.value.timestamp > $1.value.timestamp }
            cache = Dictionary(uniqueKeysWithValues: sorted.prefix(maxCacheEntries / 2).map { ($0.key, $0.value) })
        }
    }

    // MARK: - Rendering (off the main thread)

    private func render(values: [[Double?]], bounds: RainfallGridBounds) {
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        renderTask = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                let state = Self.signposter.beginInterval("Render rain map")
                defer { Self.signposter.endInterval("Render rain map", state) }
                return Self.renderImage(values: values)
            }.value
            guard !Task.isCancelled, let image, let self, self.renderGeneration == generation else { return }
            self.overlay = RainfallOverlayImage(image: image, bounds: bounds)
        }
    }

    /// CIContext is thread-safe; shared to avoid re-creating GPU state.
    nonisolated private static let ciContext = CIContext()

    /// Bilinearly upsamples the grid (row 0 = south) into an RGBA bitmap
    /// (row 0 = north), colors it, and softens it with a light blur.
    nonisolated static func renderImage(values grid: [[Double?]]) -> UIImage? {
        let rows = grid.count
        let cols = grid.first?.count ?? 0
        guard rows > 0, cols > 0 else { return nil }

        let scale = 8
        let width = cols * scale
        let height = rows * scale
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for py in 0..<height {
            let gridR = Double(rows) - (Double(py) + 0.5) / Double(scale) - 0.5
            let r0 = max(0, min(rows - 1, Int(floor(gridR))))
            let r1 = max(0, min(rows - 1, r0 + 1))
            let tr = max(0, min(1, gridR - Double(r0)))
            for px in 0..<width {
                let gridC = (Double(px) + 0.5) / Double(scale) - 0.5
                let c0 = max(0, min(cols - 1, Int(floor(gridC))))
                let c1 = max(0, min(cols - 1, c0 + 1))
                let tc = max(0, min(1, gridC - Double(c0)))

                // Weighted average over available corners (nil cells skipped).
                var mm = 0.0
                var weight = 0.0
                func add(_ value: Double?, _ w: Double) {
                    guard let value else { return }
                    mm += value * w
                    weight += w
                }
                add(grid[r0][c0], (1 - tr) * (1 - tc))
                add(grid[r0][c1], (1 - tr) * tc)
                add(grid[r1][c0], tr * (1 - tc))
                add(grid[r1][c1], tr * tc)
                guard weight > 0 else { continue }

                let (r, g, b, a) = RainfallColorScale.rgbaComponents(for: mm / weight)
                let idx = (py * width + px) * 4
                pixels[idx] = UInt8(min(255, r * a * 255))
                pixels[idx + 1] = UInt8(min(255, g * a * 255))
                pixels[idx + 2] = UInt8(min(255, b * a * 255))
                pixels[idx + 3] = UInt8(min(255, a * 255))
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else { return nil }

        let input = CIImage(cgImage: cgImage)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = input
        blur.radius = 1
        if let output = blur.outputImage?.cropped(to: input.extent),
           let blurred = ciContext.createCGImage(output, from: output.extent)
        {
            return UIImage(cgImage: blurred)
        }
        return UIImage(cgImage: cgImage)
    }
}
