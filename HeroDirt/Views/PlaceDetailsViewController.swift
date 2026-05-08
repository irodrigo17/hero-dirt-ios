import MapKit
import UIKit

final class PlaceDetailsViewController: UIViewController {
    var onDismiss: (() -> Void)?

    private let coordinate: CLLocationCoordinate2D
    private let placeID: UUID?
    private let mapItem: MKMapItem?
    private let placeStore: PlaceStore

    private var placeName = "Loading..."
    private var resolvedMapItem: MKMapItem?
    private var loadTask: Task<Void, Never>?

    private var savedPlace: Place? {
        if let placeID, let p = placeStore.places.first(where: { $0.id == placeID }) { return p }
        return placeStore.placeNear(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var effectiveMapItem: MKMapItem? { mapItem ?? resolvedMapItem }

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let actionBar = ActionBarView()
    private let loadingView = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private var dirtConditionCard: DirtConditionCardView?
    private var rainfallCard: RainfallCardView?
    private var forecastCard: RainForecastCardView?

    // MARK: - Init

    init(
        coordinate: CLLocationCoordinate2D,
        placeID: UUID?,
        mapItem: MKMapItem?,
        placeStore: PlaceStore
    ) {
        self.coordinate = coordinate
        self.placeID = placeID
        self.mapItem = mapItem
        self.placeStore = placeStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavBar()
        setupScrollView()
        setupActionBar()
        showLoading()
        startLoad()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            loadTask?.cancel()
            onDismiss?()
        }
    }

    // MARK: - Setup

    private func setupNavBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Close"
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func setupActionBar() {
        actionBar.onSave = { [weak self] in self?.toggleSaved() }
        actionBar.onMaps = { [weak self] in self?.openInMaps() }
        actionBar.onRename = { [weak self] in self?.showRenameAlert() }
        contentStack.addArrangedSubview(actionBar)
    }

    // MARK: - Loading states

    private func showLoading() {
        removeCards()
        loadingView.startAnimating()
        loadingLabel.text = "Loading rainfall data..."
        loadingLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        loadingLabel.textColor = .secondaryLabel
        loadingLabel.textAlignment = .center
        let loadingStack = UIStackView(arrangedSubviews: [loadingView, loadingLabel])
        loadingStack.axis = .vertical
        loadingStack.spacing = 8
        loadingStack.alignment = .center
        loadingStack.tag = 100
        contentStack.addArrangedSubview(loadingStack)
        actionBar.setEnabled(false)
    }

    private func showCards(summary: RainfallSummary, forecast: RainForecast?) {
        removeCards()
        let dirt = DirtConditionCardView(condition: summary.dirtCondition)
        let rain = RainfallCardView(summary: summary)
        dirtConditionCard = dirt
        rainfallCard = rain
        contentStack.addArrangedSubview(dirt)
        contentStack.addArrangedSubview(rain)
        if let forecast {
            let forecastView = RainForecastCardView(forecast: forecast)
            forecastCard = forecastView
            contentStack.addArrangedSubview(forecastView)
        }
        actionBar.setEnabled(true)
        actionBar.updateSaveButton(isSaved: savedPlace != nil)
    }

    private func showError(_ message: String) {
        removeCards()
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 36, weight: .regular)

        let titleLabel = UILabel()
        titleLabel.text = "Unable to load rainfall data"
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center

        let bodyLabel = UILabel()
        bodyLabel.text = message
        bodyLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.layoutMargins = UIEdgeInsets(top: 40, left: 0, bottom: 0, right: 0)
        stack.isLayoutMarginsRelativeArrangement = true
        contentStack.addArrangedSubview(stack)
        actionBar.setEnabled(false)
    }

    private func removeCards() {
        for view in contentStack.arrangedSubviews where view !== actionBar {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        dirtConditionCard = nil
        rainfallCard = nil
        forecastCard = nil
    }

    // MARK: - Data loading

    private func startLoad() {
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            await loadData()
        }
    }

    @MainActor
    private func loadData() async {
        placeName = "Loading..."
        updateTitle()
        showLoading()

        resolvedMapItem = await fetchMapItem(from: savedPlace?.mapItemId)
        guard !Task.isCancelled else { return }

        if let saved = savedPlace {
            placeName = saved.name
        } else if let name = mapItem?.name {
            placeName = name
        } else {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let request = MKReverseGeocodingRequest(location: location) {
                do {
                    let items = try await request.mapItems
                    guard !Task.isCancelled else { return }
                    placeName = items.first?.addressRepresentations?.cityWithContext ?? formatCoordinate()
                } catch {
                    guard !Task.isCancelled else { return }
                    placeName = formatCoordinate()
                }
            } else {
                placeName = formatCoordinate()
            }
        }
        updateTitle()

        guard !Task.isCancelled else { return }

        async let rainfallTask = WeatherService.fetchRainfall(latitude: coordinate.latitude, longitude: coordinate.longitude)
        async let forecastTask = WeatherService.fetchRainForecast(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let summary = try await rainfallTask
            guard !Task.isCancelled else { return }
            let forecast = try? await forecastTask
            guard !Task.isCancelled else { return }
            showCards(summary: summary, forecast: forecast)
        } catch {
            guard !Task.isCancelled else { return }
            showError(error.localizedDescription)
        }
    }

    private func fetchMapItem(from identifier: MKMapItem.Identifier?) async -> MKMapItem? {
        guard let identifier else { return nil }
        return try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
    }

    private func updateTitle() {
        navigationItem.title = placeName
        let subtitle = effectiveMapItem?.pointOfInterestCategory?.displayName
            ?? effectiveMapItem?.addressRepresentations?.cityWithContext
        navigationItem.subtitle = subtitle
    }

    private func formatCoordinate() -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func toggleSaved() {
        if let existing = savedPlace {
            placeStore.removePlace(existing)
        } else {
            placeStore.addPlace(Place(
                name: placeName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                mapItemId: mapItem?.identifier
            ))
        }
        actionBar.updateSaveButton(isSaved: savedPlace != nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func openInMaps() {
        if let item = effectiveMapItem {
            item.openInMaps()
        } else {
            let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
            item.name = placeName
            item.openInMaps()
        }
    }

    private func showRenameAlert() {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] field in field.text = self?.placeName }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let trimmed = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !trimmed.isEmpty else { return }
            self.placeName = trimmed
            self.updateTitle()
            if let existing = self.savedPlace {
                self.placeStore.renamePlace(existing, to: trimmed)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - Action Bar

private final class ActionBarView: UIView {
    var onSave: (() -> Void)?
    var onMaps: (() -> Void)?
    var onRename: (() -> Void)?

    private let saveButton = ActionButton(icon: "star", label: "Save", isPrimary: true)
    private let mapsButton = ActionButton(icon: "map", label: "Maps", isPrimary: false)
    private let renameButton = ActionButton(icon: "pencil", label: "Rename", isPrimary: false)

    override init(frame: CGRect) {
        super.init(frame: frame)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        mapsButton.addTarget(self, action: #selector(mapsTapped), for: .touchUpInside)
        renameButton.addTarget(self, action: #selector(renameTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [saveButton, mapsButton, renameButton])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
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

    func setEnabled(_ enabled: Bool) {
        [saveButton, mapsButton, renameButton].forEach { $0.isEnabled = enabled }
    }

    func updateSaveButton(isSaved: Bool) {
        saveButton.setIcon(isSaved ? "star.fill" : "star")
        saveButton.setLabel(isSaved ? "Saved" : "Save")
    }

    @objc private func saveTapped() { onSave?() }
    @objc private func mapsTapped() { onMaps?() }
    @objc private func renameTapped() { onRename?() }
}

private final class ActionButton: UIButton {
    private let iconView = UIImageView()
    private let labelView = UILabel()
    private let isPrimary: Bool

    init(icon: String, label: String, isPrimary: Bool) {
        self.isPrimary = isPrimary
        super.init(frame: .zero)
        setup(icon: icon, label: label)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(icon: String, label: String) {
        layer.cornerRadius = .cornerLarge
        clipsToBounds = true
        backgroundColor = isPrimary ? .systemBlue : UIColor.systemBlue.withAlphaComponent(0.1)

        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = isPrimary ? .white : .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)

        labelView.text = label
        labelView.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        labelView.textColor = isPrimary ? .white : .systemBlue
        labelView.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [iconView, labelView])
        stack.axis = .vertical
        stack.spacing = 5
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    func setIcon(_ name: String) {
        iconView.image = UIImage(systemName: name)
    }

    func setLabel(_ text: String) {
        labelView.text = text
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }
}
