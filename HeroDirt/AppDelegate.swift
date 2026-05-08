import CoreLocation
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let placeStore = PlaceStore()
    private let locationManager = CLLocationManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        locationManager.requestWhenInUseAuthorization()
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MapViewController(placeStore: placeStore)
        window?.makeKeyAndVisible()
        return true
    }
}
