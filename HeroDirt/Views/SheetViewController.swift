import Combine
import MapKit
import UIKit

// MARK: - Delegate

protocol SheetViewControllerDelegate: AnyObject {
    func sheet(_ vc: SheetViewController, didSelectPlace place: Place)
    func sheet(_ vc: SheetViewController, didSelectSearchResult item: MKMapItem)
}

// MARK: - SheetViewController

final class SheetViewController: UIViewController {
    weak var delegate: SheetViewControllerDelegate?

    var visibleRegion: MKCoordinateRegion? {
        didSet { savedPlacesVC.visibleRegion = visibleRegion }
    }

    private let placeStore: PlaceStore
    private let savedPlacesVC: SavedPlacesViewController
    private let searchResultsVC = SearchResultsViewController()
    private let searchController: UISearchController
    private var searchTask: Task<Void, Never>?

    init(placeStore: PlaceStore) {
        self.placeStore = placeStore
        self.savedPlacesVC = SavedPlacesViewController(placeStore: placeStore)
        self.searchController = UISearchController(searchResultsController: searchResultsVC)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let navVC = UINavigationController(rootViewController: savedPlacesVC)
        navVC.navigationBar.prefersLargeTitles = false

        savedPlacesVC.navigationItem.title = "Saved Places"
        savedPlacesVC.navigationItem.searchController = searchController
        savedPlacesVC.navigationItem.hidesSearchBarWhenScrolling = false

        searchController.searchResultsUpdater = self
        searchController.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search places"

        savedPlacesVC.onSelectPlace = { [weak self] place in
            guard let self else { return }
            self.delegate?.sheet(self, didSelectPlace: place)
        }
        searchResultsVC.onSelectResult = { [weak self] item in
            guard let self else { return }
            self.searchController.isActive = false
            self.delegate?.sheet(self, didSelectSearchResult: item)
        }

        addChild(navVC)
        view.addSubview(navVC.view)
        navVC.view.translatesAutoresizingMaskIntoConstraints = false
        navVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            navVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            navVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            navVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        definesPresentationContext = true
    }

    // MARK: - Search

    private func runSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = visibleRegion { request.region = region }
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            searchResultsVC.items = response.mapItems
        } catch {
            guard !Task.isCancelled else { return }
            searchResultsVC.items = []
        }
    }
}

// MARK: - UISearchResultsUpdating

extension SheetViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchTask?.cancel()
        let query = searchController.searchBar.text ?? ""
        guard !query.isEmpty else {
            searchResultsVC.isSearching = false
            searchResultsVC.items = []
            return
        }
        searchResultsVC.isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await runSearch(query: query)
        }
    }
}

// MARK: - UISearchControllerDelegate

extension SheetViewController: UISearchControllerDelegate {
    func willPresentSearchController(_ searchController: UISearchController) {
        (presentationController as? UISheetPresentationController)?.animateChanges {
            (self.presentationController as? UISheetPresentationController)?.selectedDetentIdentifier = .large
        }
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        (presentationController as? UISheetPresentationController)?.animateChanges {
            (self.presentationController as? UISheetPresentationController)?.selectedDetentIdentifier = .medium
        }
    }
}
