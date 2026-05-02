import Foundation
import Combine
import MapKit
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct RainfallGridBounds: Equatable {
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

final class RainfallGridService: ObservableObject {

    // MARK: - Public state

    @Published private(set) var isLoading = false
    @Published private(set) var gridVersion: Int = 0

    // MARK: - Grid data

    private var coarseGrid: [[RainfallSummary?]] = []
    private var coarseRows = 0
    private var coarseCols = 0
    private var gridLatStep: Double = 0
    private var gridLonStep: Double = 0
    private(set) var gridBounds: RainfallGridBounds?

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let latSlot: Int
        let lonSlot: Int
    }

    private struct CacheEntry {
        let summary: RainfallSummary
        let timestamp: Date
    }

    private var cache: [CacheKey: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 15 * 60 // 15 minutes

    // MARK: - Debounce

    private var updateTask: Task<Void, Never>?
    private var lastRegion: MKCoordinateRegion?

    // MARK: - Network

    private let gridSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Image cache

    private var imageCache: [RainfallTimeframe: UIImage] = [:]
    private var imageCacheVersion: Int = -1
    private let ciContext = CIContext()

    // MARK: - Public API

    func updateRegion(_ region: MKCoordinateRegion) {
        lastRegion = region
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.fetchGrid(for: region)
        }
    }

    func refetch() {
        guard let region = lastRegion else { return }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            await self?.fetchGrid(for: region)
        }
    }

    // MARK: - Image rendering

    func rainfallImage(for timeframe: RainfallTimeframe) -> UIImage? {
        // Return cached image if grid hasn't changed
        if imageCacheVersion == gridVersion, let cached = imageCache[timeframe] {
            return cached
        }

        guard coarseRows > 0, coarseCols > 0 else { return nil }

        let scale = 8 // pixels per coarse cell
        let imgWidth = coarseCols * scale
        let imgHeight = coarseRows * scale

        var pixelData = [UInt8](repeating: 0, count: imgWidth * imgHeight * 4)

        for py in 0..<imgHeight {
            for px in 0..<imgWidth {
                // Map pixel to fractional coarse grid position
                // Bitmap row 0 = top = north (maxLat), coarse grid row 0 = south (minLat)
                let gridR = Double(coarseRows) - (Double(py) + 0.5) / Double(scale) - 0.5
                let gridC = (Double(px) + 0.5) / Double(scale) - 0.5

                let r0 = max(0, min(coarseRows - 1, Int(floor(gridR))))
                let r1 = max(0, min(coarseRows - 1, r0 + 1))
                let c0 = max(0, min(coarseCols - 1, Int(floor(gridC))))
                let c1 = max(0, min(coarseCols - 1, c0 + 1))

                let tr = max(0, min(1, gridR - Double(r0)))
                let tc = max(0, min(1, gridC - Double(c0)))

                // Weighted interpolation using available corners (handles nil cells gracefully)
                let w00 = (1 - tr) * (1 - tc)
                let w01 = (1 - tr) * tc
                let w10 = tr * (1 - tc)
                let w11 = tr * tc

                var mm = 0.0
                var totalWeight = 0.0
                if let s = coarseGrid[r0][c0] { mm += timeframe.amount(from: s) * w00; totalWeight += w00 }
                if let s = coarseGrid[r0][c1] { mm += timeframe.amount(from: s) * w01; totalWeight += w01 }
                if let s = coarseGrid[r1][c0] { mm += timeframe.amount(from: s) * w10; totalWeight += w10 }
                if let s = coarseGrid[r1][c1] { mm += timeframe.amount(from: s) * w11; totalWeight += w11 }
                guard totalWeight > 0 else { continue }
                mm /= totalWeight
                let (r, g, b, a) = RainfallColorScale.rgbaComponents(for: mm)

                let idx = (py * imgWidth + px) * 4
                pixelData[idx]     = UInt8(min(255, r * a * 255))
                pixelData[idx + 1] = UInt8(min(255, g * a * 255))
                pixelData[idx + 2] = UInt8(min(255, b * a * 255))
                pixelData[idx + 3] = UInt8(min(255, a * 255))
            }
        }

        guard let rawImage = createCGImage(from: &pixelData, width: imgWidth, height: imgHeight) else { return nil }

        // Apply Gaussian blur for extra smoothness
        let blurred = applyBlur(to: rawImage, radius: 1) ?? UIImage(cgImage: rawImage)

        // Cache the result
        if imageCacheVersion != gridVersion {
            imageCache.removeAll()
            imageCacheVersion = gridVersion
        }
        imageCache[timeframe] = blurred

        return blurred
    }

    private func createCGImage(from pixelData: inout [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixelData)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
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
    }

    private func applyBlur(to cgImage: CGImage, radius: CGFloat) -> UIImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = ciImage
        blur.radius = Float(radius)
        guard let output = blur.outputImage else { return nil }
        // Blur expands bounds, crop back to original
        let cropped = output.cropped(to: ciImage.extent)
        guard let result = ciContext.createCGImage(cropped, from: cropped.extent) else { return nil }
        return UIImage(cgImage: result)
    }

    private func bilerp(_ v00: Double, _ v01: Double, _ v10: Double, _ v11: Double, tr: Double, tc: Double) -> Double {
        let top = v00 + (v01 - v00) * tc
        let bot = v10 + (v11 - v10) * tc
        return top + (bot - top) * tr
    }

    // MARK: - Grid fetching

    @MainActor
    private func fetchGrid(for region: MKCoordinateRegion) async {
        let maxCells = 12
        let latStep = max(0.1, region.span.latitudeDelta / Double(maxCells))
        let lonStep = max(0.1, region.span.longitudeDelta / Double(maxCells))

        // Pad region by one cell on each side to cover area behind safe area insets
        // (search bar, tab bar) where the map is visible but the reported region is smaller
        let padding = 1.5
        let minLat = region.center.latitude - region.span.latitudeDelta / 2 - latStep * padding
        let minLon = region.center.longitude - region.span.longitudeDelta / 2 - lonStep * padding
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2 + latStep * padding
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2 + lonStep * padding

        struct GridPoint {
            let lat: Double
            let lon: Double
            let row: Int
            let col: Int
            let key: CacheKey
        }

        // Compute rows/cols deterministically to ensure full coverage
        let rows = max(1, Int(ceil((maxLat - minLat) / latStep)))
        let cols = max(1, Int(ceil((maxLon - minLon) / lonStep)))

        var points: [GridPoint] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let lat = minLat + latStep / 2 + Double(r) * latStep
                let lon = minLon + lonStep / 2 + Double(c) * lonStep
                let key = CacheKey(latSlot: Int(lat * 100), lonSlot: Int(lon * 100))
                points.append(GridPoint(lat: lat, lon: lon, row: r, col: c, key: key))
            }
        }

        // Prune expired cache entries
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }

        // Split into cached and uncached
        let uncachedPoints = points.filter { cache[$0.key] == nil }

        guard !Task.isCancelled else { return }

        if !uncachedPoints.isEmpty {
            isLoading = true

            let session = gridSession
            await withTaskGroup(of: (CacheKey, RainfallSummary?).self) { group in
                let maxConcurrent = 4
                var inflight = 0

                for point in uncachedPoints {
                    if inflight >= maxConcurrent {
                        if let (key, summary) = await group.next() {
                            if let summary {
                                cache[key] = CacheEntry(summary: summary, timestamp: Date())
                            }
                            inflight -= 1
                        }
                    }
                    group.addTask {
                        do {
                            let summary = try await WeatherService.fetchRainfall(
                                latitude: point.lat,
                                longitude: point.lon,
                                session: session
                            )
                            return (point.key, summary)
                        } catch {
                            return (point.key, nil)
                        }
                    }
                    inflight += 1
                }

                for await (key, summary) in group {
                    if let summary {
                        cache[key] = CacheEntry(summary: summary, timestamp: Date())
                    }
                }
            }

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            isLoading = false
        }

        // Build coarse 2D grid
        var grid = [[RainfallSummary?]](repeating: [RainfallSummary?](repeating: nil, count: cols), count: rows)
        for point in points {
            if let entry = cache[point.key] {
                grid[point.row][point.col] = entry.summary
            }
        }

        self.coarseGrid = grid
        self.coarseRows = rows
        self.coarseCols = cols
        self.gridLatStep = latStep
        self.gridLonStep = lonStep
        self.gridBounds = RainfallGridBounds(
            minLat: minLat,
            maxLat: minLat + Double(rows) * latStep,
            minLon: minLon,
            maxLon: minLon + Double(cols) * lonStep
        )
        self.gridVersion += 1
    }
}
