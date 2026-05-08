import Combine
import MapKit
import UIKit

final class SavedPlacesViewController: UITableViewController {
    var onSelectPlace: (Place) -> Void = { _ in }
    var visibleRegion: MKCoordinateRegion?

    private let placeStore: PlaceStore
    private var cancellables = Set<AnyCancellable>()

    private var rainfallData: [UUID: RainfallSummary] = [:]
    private var loadingPlaces: Set<UUID> = []
    private var errors: [UUID: String] = [:]
    private var loadTask: Task<Void, Never>?

    init(placeStore: PlaceStore) {
        self.placeStore = placeStore
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Saved Places"
        tableView.register(PlaceCell.self, forCellReuseIdentifier: PlaceCell.reuseID)
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        tableView.refreshControl = refresh

        placeStore.$places
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.placesDidChange() }
            .store(in: &cancellables)

        Task { await loadAllRainfall() }
    }

    private func placesDidChange() {
        updateEmptyState()
        tableView.reloadData()
        loadTask?.cancel()
        loadTask = Task { await loadAllRainfall() }
    }

    @objc private func pullToRefresh() {
        Task {
            await loadAllRainfall()
            tableView.refreshControl?.endRefreshing()
        }
    }

    private func updateEmptyState() {
        if placeStore.places.isEmpty {
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "star")
            config.text = "No saved places"
            config.secondaryText = "Long-press anywhere on the map to check rainfall, then tap the star to save it here."
            contentUnavailableConfiguration = config
        } else {
            contentUnavailableConfiguration = nil
        }
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        placeStore.places.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PlaceCell.reuseID, for: indexPath) as! PlaceCell
        let place = placeStore.places[indexPath.row]
        cell.configure(
            place: place,
            rainfall: rainfallData[place.id],
            isLoading: loadingPlaces.contains(place.id),
            error: errors[place.id]
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        placeStore.removePlaces(at: IndexSet(integer: indexPath.row))
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectPlace(placeStore.places[indexPath.row])
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let place = placeStore.places[indexPath.row]
        let rename = UIContextualAction(style: .normal, title: "Rename") { [weak self] _, _, completion in
            self?.showRenameAlert(for: place)
            completion(true)
        }
        rename.image = UIImage(systemName: "pencil")
        rename.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [rename])
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.placeStore.removePlaces(at: IndexSet(integer: indexPath.row))
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: - Rename

    private func showRenameAlert(for place: Place) {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = place.name }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            let trimmed = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            if !trimmed.isEmpty { self?.placeStore.renamePlace(place, to: trimmed) }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Rainfall loading

    private func loadAllRainfall() async {
        let placesToLoad = placeStore.places.filter {
            rainfallData[$0.id] == nil && !loadingPlaces.contains($0.id)
        }
        guard !placesToLoad.isEmpty else { return }

        for place in placesToLoad { loadingPlaces.insert(place.id) }
        reloadVisibleCells(for: placesToLoad.map(\.id))

        await withTaskGroup(of: (UUID, Result<RainfallSummary, Error>).self) { group in
            for place in placesToLoad {
                group.addTask {
                    do {
                        let s = try await WeatherService.fetchRainfall(latitude: place.latitude, longitude: place.longitude)
                        return (place.id, .success(s))
                    } catch {
                        return (place.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                loadingPlaces.remove(id)
                switch result {
                case .success(let s): rainfallData[id] = s; errors[id] = nil
                case .failure(let e): errors[id] = e.localizedDescription
                }
                reloadVisibleCells(for: [id])
            }
        }
    }

    private func reloadVisibleCells(for ids: [UUID]) {
        let indexes = ids.compactMap { id in
            placeStore.places.firstIndex(where: { $0.id == id })
        }.map { IndexPath(row: $0, section: 0) }
        tableView.reloadRows(at: indexes, with: .none)
    }
}

// MARK: - UISearchResultsUpdating

extension SavedPlacesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        // Handled by SheetViewController which drives SearchResultsViewController
    }
}

// MARK: - Place Cell

final class PlaceCell: UITableViewCell {
    static let reuseID = "PlaceCell"

    private let nameLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
    private let conditionBadge = UIView()
    private let conditionLabel = UILabel()
    private let conditionIcon = UIImageView()
    private let lastRainLabel = UILabel()
    private let progressView = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private let tilesStack = UIStackView()
    private var tileViews: [CompactTileView] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        selectionStyle = .default

        nameLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail

        chevron.tintColor = .secondaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [nameLabel, chevron])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 8

        // Condition badge
        conditionIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12)
        conditionIcon.setContentHuggingPriority(.required, for: .horizontal)
        conditionLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        let badgeContent = UIStackView(arrangedSubviews: [conditionIcon, conditionLabel])
        badgeContent.axis = .horizontal
        badgeContent.spacing = 4
        badgeContent.alignment = .center
        badgeContent.translatesAutoresizingMaskIntoConstraints = false
        conditionBadge.addSubview(badgeContent)
        conditionBadge.layer.cornerRadius = 8
        NSLayoutConstraint.activate([
            badgeContent.topAnchor.constraint(equalTo: conditionBadge.topAnchor, constant: 6),
            badgeContent.bottomAnchor.constraint(equalTo: conditionBadge.bottomAnchor, constant: -6),
            badgeContent.leadingAnchor.constraint(equalTo: conditionBadge.leadingAnchor, constant: 8),
            badgeContent.trailingAnchor.constraint(equalTo: conditionBadge.trailingAnchor, constant: -8),
        ])

        lastRainLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        lastRainLabel.textColor = .secondaryLabel

        let badgeSpacer = UIView()
        let badgeRow = UIStackView(arrangedSubviews: [conditionBadge, badgeSpacer, lastRainLabel])
        badgeRow.axis = .horizontal
        badgeRow.alignment = .center

        // Progress / error / tiles
        progressView.hidesWhenStopped = true

        errorLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 2

        tileViews = ["1d", "2d", "3d", "7d"].map { CompactTileView(label: $0) }
        tileViews.forEach { tilesStack.addArrangedSubview($0) }
        tilesStack.axis = .horizontal
        tilesStack.spacing = 6
        tilesStack.distribution = .fillEqually

        let mainStack = UIStackView(arrangedSubviews: [topRow, badgeRow, progressView, errorLabel, tilesStack])
        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    func configure(place: Place, rainfall: RainfallSummary?, isLoading: Bool, error: String?) {
        nameLabel.text = place.name

        progressView.isHidden = !isLoading
        if isLoading { progressView.startAnimating() } else { progressView.stopAnimating() }
        errorLabel.isHidden = error == nil || isLoading
        errorLabel.text = error
        tilesStack.isHidden = rainfall == nil || isLoading
        badgeRowViews(hidden: rainfall == nil || isLoading)

        if let rainfall {
            let condition = rainfall.dirtCondition
            conditionIcon.image = UIImage(systemName: condition.icon)
            conditionIcon.tintColor = condition.color
            conditionLabel.text = condition.label
            conditionLabel.textColor = condition.color
            conditionBadge.backgroundColor = condition.color.withAlphaComponent(0.12)

            lastRainLabel.text = lastRainText(for: rainfall)

            let values = [rainfall.last1Day, rainfall.last2Days, rainfall.last3Days, rainfall.last7Days]
            zip(tileViews, values).forEach { $0.configure(value: $1) }
        }
    }

    private func badgeRowViews(hidden: Bool) {
        conditionBadge.isHidden = hidden
        lastRainLabel.isHidden = hidden
    }

    private func lastRainText(for rainfall: RainfallSummary) -> String {
        guard let days = rainfall.daysSinceLastRain else { return "30d+" }
        switch days {
        case 0: return "Today"
        case 1: return "1d ago"
        default: return "\(days)d ago"
        }
    }
}

// MARK: - Compact Tile

private final class CompactTileView: UIView {
    private let labelView = UILabel()
    private let valueView = UILabel()

    init(label: String) {
        super.init(frame: .zero)
        layer.cornerRadius = .cornerSmall
        clipsToBounds = true

        labelView.text = label
        labelView.font = UIFont.systemFont(ofSize: 10)
        labelView.textColor = .secondaryLabel
        labelView.textAlignment = .center

        valueView.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        valueView.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [labelView, valueView])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(value: Double) {
        valueView.text = value.formatMillimeters()
        valueView.textColor = value > 0 ? .systemBlue : .secondaryLabel
        backgroundColor = value > 0 ? UIColor.systemBlue.withAlphaComponent(0.08) : UIColor.systemGray.withAlphaComponent(0.05)
    }
}
