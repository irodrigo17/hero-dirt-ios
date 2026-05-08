import UIKit

extension Double {
    func formatMillimeters() -> String {
        if self >= 100 { return "100+" }
        return self < 10 ? String(format: "%.1f", self) : String(format: "%.0f", self)
    }
}

extension CGFloat {
    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 12
    static let cornerLarge: CGFloat = 16
}

final class CardHeaderView: UIView {
    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, spacer, subtitleLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
