import UIKit

final class RainfallCardView: UIView {
    init(summary: RainfallSummary) {
        super.init(frame: .zero)
        setup(summary: summary)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(summary: RainfallSummary) {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = .cornerMedium
        clipsToBounds = true

        let header = CardHeaderView(title: "Rainfall", subtitle: "Past days")

        let tilesRow = UIStackView(arrangedSubviews: [
            makeTile("1 day", value: summary.last1Day),
            makeTile("2 days", value: summary.last2Days),
            makeTile("3 days", value: summary.last3Days),
            makeTile("7 days", value: summary.last7Days),
        ])
        tilesRow.axis = .horizontal
        tilesRow.spacing = 10
        tilesRow.distribution = .fillEqually

        let divider = UIView()
        divider.backgroundColor = .separator

        let lastRainRow = makeLastRainRow(summary: summary)

        let stack = UIStackView(arrangedSubviews: [header, tilesRow, divider, lastRainRow])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func makeTile(_ label: String, value: Double) -> UIView {
        let container = UIView()
        container.backgroundColor = value > 0 ? UIColor.systemBlue.withAlphaComponent(0.08) : UIColor.systemGray.withAlphaComponent(0.06)
        container.layer.cornerRadius = 8
        container.clipsToBounds = true

        let labelView = UILabel()
        labelView.text = label
        labelView.font = UIFont.preferredFont(forTextStyle: .caption1)
        labelView.textColor = .secondaryLabel
        labelView.textAlignment = .center

        let valueView = UILabel()
        valueView.text = value.formatMillimeters()
        valueView.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        valueView.textColor = .systemBlue
        valueView.textAlignment = .center

        let unitView = UILabel()
        unitView.text = "mm"
        unitView.font = UIFont.preferredFont(forTextStyle: .caption2)
        unitView.textColor = .secondaryLabel
        unitView.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [labelView, valueView, unitView])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
        ])
        return container
    }

    private func makeLastRainRow(summary: RainfallSummary) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "cloud.rain"))
        icon.tintColor = .systemBlue
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let lastRainLabel = UILabel()
        lastRainLabel.text = "Last rain:"
        lastRainLabel.textColor = .secondaryLabel
        lastRainLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        lastRainLabel.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = UIView()

        let valueLabel = UILabel()
        valueLabel.text = lastRainText(for: summary)
        valueLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        valueLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [icon, lastRainLabel, spacer, valueLabel])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        return row
    }

    private func lastRainText(for summary: RainfallSummary) -> String {
        guard let days = summary.daysSinceLastRain else { return "30+ days ago" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}
