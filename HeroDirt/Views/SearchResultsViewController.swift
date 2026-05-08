import MapKit
import UIKit

final class SearchResultsViewController: UITableViewController {
    var onSelectResult: (MKMapItem) -> Void = { _ in }

    var isSearching: Bool = false {
        didSet { tableView.reloadData() }
    }
    var items: [MKMapItem] = [] {
        didSet { isSearching = false }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .onDrag
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        (isSearching || !items.isEmpty) ? max(items.count, 1) : 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSearching {
            let cell = UITableViewCell()
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            spinner.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                cell.contentView.heightAnchor.constraint(equalToConstant: 60),
            ])
            cell.selectionStyle = .none
            return cell
        }

        if items.isEmpty {
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "magnifyingglass")
            config.text = "No results found"
            config.secondaryText = "Try a different search term"
            let cell = UITableViewCell()
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            return cell
        }

        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = item.name ?? "Unknown"
        let subtitle = item.addressRepresentations?.cityWithContext ?? item.pointOfInterestCategory?.displayName
        if let subtitle, subtitle != item.name {
            config.secondaryText = subtitle
        }
        config.image = categoryIcon(for: item.pointOfInterestCategory)
        config.imageProperties.cornerRadius = 15
        cell.contentConfiguration = config
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isSearching, !items.isEmpty else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectResult(items[indexPath.row])
    }

    // MARK: - Helpers

    private func categoryIcon(for category: MKPointOfInterestCategory?) -> UIImage? {
        let symbol = category?.sfSymbol ?? "mappin"
        let color = category?.iconColor ?? .systemPink
        let size: CGFloat = 30
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()
            let iconConfig = UIImage.SymbolConfiguration(pointSize: size * 0.45, weight: .medium)
            if let icon = UIImage(systemName: symbol, withConfiguration: iconConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let iconSize = icon.size
                let origin = CGPoint(x: (size - iconSize.width) / 2, y: (size - iconSize.height) / 2)
                icon.draw(at: origin)
            }
        }
    }
}
