import SwiftUI

/// User preference for how rain amounts are displayed. `.automatic` follows the
/// device's measurement system (inches for US, millimeters elsewhere).
enum RainUnitPreference: String, CaseIterable, Identifiable {
    case automatic
    case millimeters
    case inches

    static let storageKey = "rainUnitPreference"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .millimeters: return "Millimeters"
        case .inches: return "Inches"
        }
    }

    func resolved(locale: Locale = .current) -> RainUnit {
        switch self {
        case .millimeters: return .millimeters
        case .inches: return .inches
        case .automatic: return locale.measurementSystem == .us ? .inches : .millimeters
        }
    }
}

/// The concrete unit used to render rain amounts. All data is stored in millimeters.
enum RainUnit: Sendable {
    case millimeters
    case inches

    static let mmPerInch = 25.4

    var symbol: String {
        switch self {
        case .millimeters: return "mm"
        case .inches: return "in"
        }
    }

    var spokenName: String {
        switch self {
        case .millimeters: return "millimeters"
        case .inches: return "inches"
        }
    }

    /// Formats a millimeter amount as a bare number in this unit.
    func format(_ mm: Double) -> String {
        switch self {
        case .millimeters:
            return mm < 10 ? String(format: "%.1f", mm) : String(format: "%.0f", mm)
        case .inches:
            let inches = mm / Self.mmPerInch
            if inches == 0 { return "0" }
            if inches < 0.01 { return "<.01" }
            return inches < 1 ? String(format: "%.2f", inches) : String(format: "%.1f", inches)
        }
    }

    /// Formats a millimeter amount with its unit symbol, e.g. "4.2 mm" or "0.17 in".
    func formatWithUnit(_ mm: Double) -> String {
        "\(format(mm)) \(symbol)"
    }

    func accessibilityText(_ mm: Double) -> String {
        "\(format(mm)) \(spokenName)"
    }
}

// MARK: - Environment

private struct RainUnitKey: EnvironmentKey {
    static let defaultValue: RainUnit = RainUnitPreference.automatic.resolved()
}

extension EnvironmentValues {
    var rainUnit: RainUnit {
        get { self[RainUnitKey.self] }
        set { self[RainUnitKey.self] = newValue }
    }
}
