import CoreLocation
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let placeStore = PlaceStore()
    private let locationManager = CLLocationManager()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        locationManager.requestWhenInUseAuthorization()
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = MapViewController(placeStore: placeStore)
        window?.makeKeyAndVisible()
    }
}
