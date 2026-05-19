import Foundation

// MARK: - SoilOverride

struct SoilOverride: Codable, Hashable, Sendable {

    var textureClass: TextureClass
    var exposure: Exposure

    enum TextureClass: String, Codable, CaseIterable, Hashable {
        case sand = "Sand"
        case sandyLoam = "Sandy Loam"
        case loam = "Loam"
        case clayLoam = "Clay Loam"
        case clay = "Clay"

        var sandFraction: Double {
            switch self {
            case .sand: return 0.90
            case .sandyLoam: return 0.65
            case .loam: return 0.40
            case .clayLoam: return 0.25
            case .clay: return 0.10
            }
        }

        var clayFraction: Double {
            switch self {
            case .sand: return 0.05
            case .sandyLoam: return 0.10
            case .loam: return 0.20
            case .clayLoam: return 0.35
            case .clay: return 0.55
            }
        }
    }

    enum Exposure: String, Codable, CaseIterable, Hashable {
        case sunny = "Sunny"
        case partial = "Partial"
        case shaded = "Shaded"

        var dryingMultiplier: Double {
            switch self {
            case .sunny: return 1.3
            case .partial: return 1.0
            case .shaded: return 0.65
            }
        }

        var icon: String {
            switch self {
            case .sunny: return "sun.max"
            case .partial: return "cloud.sun"
            case .shaded: return "tree"
            }
        }
    }

    var asSoilData: SoilData {
        SoilData(
            sandFraction: textureClass.sandFraction,
            clayFraction: textureClass.clayFraction,
            isEstimated: false,
            dryingRateMultiplier: exposure.dryingMultiplier
        )
    }
}

// MARK: - SoilData

struct SoilData: Sendable {
    let sandFraction: Double           // 0.0–1.0
    let clayFraction: Double           // 0.0–1.0
    let isEstimated: Bool              // true when using loam fallback, not from API
    let dryingRateMultiplier: Double   // 1.0 = reference; <1 slower (shade), >1 faster (sun)

    init(
        sandFraction: Double,
        clayFraction: Double,
        isEstimated: Bool = false,
        dryingRateMultiplier: Double = 1.0
    ) {
        self.sandFraction = sandFraction
        self.clayFraction = clayFraction
        self.isEstimated = isEstimated
        self.dryingRateMultiplier = dryingRateMultiplier
    }

    var fieldCapacity: Double { 20.0 + 25.0 * (1.0 - sandFraction) }
    var dryingRate: Double { (0.6 + 0.9 * sandFraction) * dryingRateMultiplier }

    // Simplified USDA texture triangle classification
    var textureLabel: String {
        let s = sandFraction
        let c = clayFraction
        if s >= 0.85 { return "Sand" }
        if s >= 0.70 && c < 0.15 { return "Loamy Sand" }
        if s >= 0.52 && c < 0.20 { return "Sandy Loam" }
        if s >= 0.45 && c >= 0.35 { return "Sandy Clay" }
        if c >= 0.40 { return "Clay" }
        if c >= 0.27 { return "Clay Loam" }
        if s < 0.20 { return "Silt Loam" }
        return "Loam"
    }

    static let loam = SoilData(sandFraction: 0.4, clayFraction: 0.2, isEstimated: true)
}
