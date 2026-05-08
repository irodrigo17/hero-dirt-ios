import UIKit

final class DirtConditionCardView: UIView {
    private let iconView = UIImageView()
    private let conditionLabel = UILabel()
    private let descriptionLabel = UILabel()

    init(condition: DirtCondition) {
        super.init(frame: .zero)
        setup()
        configure(condition: condition)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(condition: DirtCondition) {
        iconView.image = UIImage(systemName: condition.icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .regular))
        iconView.tintColor = condition.color
        conditionLabel.text = condition.label
        conditionLabel.textColor = condition.color
        descriptionLabel.text = condition.description
    }

    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = .cornerMedium
        clipsToBounds = true

        let header = CardHeaderView(title: "Dirt Conditions", subtitle: "Estimate")

        iconView.contentMode = .scaleAspectFit

        conditionLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        conditionLabel.adjustsFontSizeToFitWidth = true

        descriptionLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [conditionLabel, descriptionLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let conditionRow = UIStackView(arrangedSubviews: [iconView, textStack])
        conditionRow.axis = .horizontal
        conditionRow.spacing = 16
        conditionRow.alignment = .center

        let divider = UIView()
        divider.backgroundColor = .separator

        let footnote = UILabel()
        footnote.text = "Based on the 1 day per inch of rainfall rule of thumb. Actual conditions vary by soil type, shade, and exposure."
        footnote.font = UIFont.preferredFont(forTextStyle: .caption1)
        footnote.textColor = .secondaryLabel
        footnote.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [header, conditionRow, divider, footnote])
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
            iconView.widthAnchor.constraint(equalToConstant: 44),
        ])
    }
}
