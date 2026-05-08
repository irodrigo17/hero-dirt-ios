import MapKit
import UIKit

final class SearchResultsViewController: UITableViewController {
    var onSelectResult: (MKMapItem) -> Void = { _ in }
    var items: [MKMapItem] = [] {
        didSet { tableView.reloadData() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .onDrag
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.isEmpty ? 1 : items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
        cell.contentConfiguration = config
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !items.isEmpty else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectResult(items[indexPath.row])
    }

    // MARK: - Helpers

    private func categoryIcon(for category: MKPointOfInterestCategory?) -> UIImage? {
        let symbol = category?.sfSymbol ?? "mappin"
        let color = category?.iconColor ?? .systemPink
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, color]))
        return UIImage(systemName: symbol, withConfiguration: config)?
            .withRenderingMode(.alwaysOriginal)
    }
}
