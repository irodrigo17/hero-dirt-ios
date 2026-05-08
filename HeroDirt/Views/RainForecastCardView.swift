import UIKit

final class RainForecastCardView: UIView {
    init(forecast: RainForecast) {
        super.init(frame: .zero)
        setup(forecast: forecast)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(forecast: RainForecast) {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = .cornerMedium
        clipsToBounds = true

        let header = CardHeaderView(title: "Rain Forecast", subtitle: "Next days")

        let tilesRow = UIStackView(arrangedSubviews: [
            makeTile("1 day", value: forecast.next1Day),
            makeTile("2 days", value: forecast.next2Days),
            makeTile("3 days", value: forecast.next3Days),
            makeTile("7 days", value: forecast.next7Days),
        ])
        tilesRow.axis = .horizontal
        tilesRow.spacing = 10
        tilesRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [header, tilesRow])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
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
}
