import SwiftUI

/// Calendar over the observed records already fetched for the trail. Missing
/// dates remain missing; they must never be presented as dry days.
struct RainHistoryCalendarView: View {
    let days: [DailyWeatherData]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rainUnit) private var unit
    @State private var month: Date
    private let calendar = Calendar.current

    init(days: [DailyWeatherData]) {
        self.days = days.filter { !$0.isForecast }
        let latest = self.days.map(\.date).max() ?? .now
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: latest)!.start)
    }

    private var records: [Date: DailyWeatherData] {
        Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map {
            calendar.date(byAdding: .day, value: $0 - 1, to: month)
        }
    }

    private var firstMonth: Date {
        calendar.dateInterval(of: .month, for: days.map(\.date).min() ?? month)!.start
    }

    private var lastMonth: Date {
        calendar.dateInterval(of: .month, for: days.map(\.date).max() ?? month)!.start
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous month")
                            .disabled(month <= firstMonth)
                        Spacer()
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .font(.headline)
                            .accessibilityIdentifier("Rain calendar month")
                        Spacer()
                        Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Next month")
                            .disabled(month >= lastMonth)
                    }
                    .padding(.vertical, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                        ForEach(0..<7, id: \.self) { index in
                            Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                            if let date {
                                dayCell(date)
                            } else {
                                Color.clear.frame(minHeight: 60)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    Text("Amounts in \(unit.symbol). A dash means no observed data. Today's amount includes only rain recorded so far.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let earliest = days.map(\.date).min(), let latest = days.map(\.date).max() {
                        Text("Available history: \(earliest.formatted(date: .abbreviated, time: .omitted)) – \(latest.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Source: Open-Meteo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Rain Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let record = records[calendar.startOfDay(for: date)]
        return VStack(spacing: 7) {
            Text(date.formatted(.dateTime.day()))
                .font(.caption.weight(calendar.isDateInToday(date) ? .bold : .regular))
                .foregroundStyle(calendar.isDateInToday(date) ? Color.blue : .primary)
            Text(record.map { unit.format($0.amount) } ?? "—")
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(record == nil ? Color.clear : Color.blue.opacity(record!.amount > 0 ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(record.map { unit.accessibilityText($0.amount) } ?? String(localized: "No observed data"))")
    }

    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) { month = next }
    }
}
