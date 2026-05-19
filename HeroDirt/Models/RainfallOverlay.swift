import Foundation

enum RainfallTimeframe: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case twoDays = "2d"
    case threeDays = "3d"
    case sevenDays = "7d"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneDay: return "1 Day"
        case .twoDays: return "2 Days"
        case .threeDays: return "3 Days"
        case .sevenDays: return "7 Days"
        }
    }

    var pastDays: Int {
        switch self {
        case .oneDay: return 1
        case .twoDays: return 2
        case .threeDays: return 3
        case .sevenDays: return 7
        }
    }

    func amount(from summary: RainfallSummary) -> Double {
        switch self {
        case .oneDay: return summary.last1Day
        case .twoDays: return summary.last2Days
        case .threeDays: return summary.last3Days
        case .sevenDays: return summary.last7Days
        }
    }
}
