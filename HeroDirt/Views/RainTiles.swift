import SwiftUI

// Shared building blocks used by both the saved places list and the place
// details sheet, so the two surfaces read as one design.

// MARK: - Rain tiles

struct RainTile: View {
    enum Style { case regular, compact }

    let label: String
    let mm: Double
    var style: Style = .regular

    @Environment(\.rainUnit) private var unit

    var body: some View {
        VStack(spacing: style == .regular ? 4 : 2) {
            Text(label)
                .font(style == .regular ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if style == .regular {
                // Unit on its own line so values never truncate in narrow
                // columns (landscape sidebar, folded iPhone Duo).
                Text(unit.format(mm))
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(mm > 0 ? Color.blue : Color.secondary)
                Text(unit.symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(unit.format(mm))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(unit.symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(mm > 0 ? Color.blue : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .padding(.vertical, style == .regular ? 10 : 6)
        .background(
            mm > 0 ? Color.blue.opacity(0.08) : Color.gray.opacity(0.06),
            in: RoundedRectangle(cornerRadius: style == .regular ? .cornerSmall + 2 : .cornerSmall)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(unit.accessibilityText(mm))")
    }
}

struct RainTilesRow: View {
    let tiles: [(label: String, mm: Double)]
    var style: RainTile.Style = .regular

    var body: some View {
        HStack(spacing: style == .regular ? 10 : 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                RainTile(label: tile.label, mm: tile.mm, style: style)
            }
        }
    }
}

extension RainfallSummary {
    var pastTiles: [(label: String, mm: Double)] {
        [("Today", last1Day), ("2 days", last2Days), ("3 days", last3Days), ("7 days", last7Days)]
    }

    var lastRainText: String {
        guard let days = daysSinceLastRain else { return "Over a month ago" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}

extension RainForecast {
    var nextTiles: [(label: String, mm: Double)] {
        [("Today", next1Day), ("2 days", next2Days), ("3 days", next3Days), ("7 days", next7Days)]
    }
}

// MARK: - Condition badge

struct ConditionBadge: View {
    let condition: DirtCondition

    var body: some View {
        Label(condition.label, systemImage: condition.icon)
            .labelStyle(.titleAndIcon)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(condition.color)
            .labelIconToTitleSpacing(4)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(condition.color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Trail conditions: \(condition.label)")
    }
}

// MARK: - Card container

struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cornerMedium))
    }
}
