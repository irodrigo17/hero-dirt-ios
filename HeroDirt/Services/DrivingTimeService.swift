import CoreLocation
import MapKit

protocol DrivingTimeProviding: Sendable {
    @MainActor func travelTime(to destination: CLLocationCoordinate2D) async -> TimeInterval?
}

struct LiveDrivingTimeProvider: DrivingTimeProviding {
    func travelTime(to destination: CLLocationCoordinate2D) async -> TimeInterval? {
        guard let location = await DrivingLocationRequest().location(), !Task.isCancelled else { return nil }
        return await travelTime(from: location, to: destination)
    }

    @MainActor
    func travelTime(from location: CLLocation, to destination: CLLocationCoordinate2D) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: location, address: nil)
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil
        )
        request.transportType = .automobile
        request.departureDate = .now
        let directions = MKDirections(request: request)
        return await withTaskCancellationHandler {
            try? await directions.calculateETA().expectedTravelTime
        } onCancel: {
            Task { @MainActor in directions.cancel() }
        }
    }
}

/// One location fix per estimate; stop listening on success, denial, timeout,
/// or cancellation rather than keeping GPS running on the details screen.
@MainActor
private final class DrivingLocationRequest: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeout: Task<Void, Never>?

    func location() async -> CLLocation? {
        guard !Task.isCancelled else { return nil }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                timeout = Task {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    finish(nil)
                }
                requestIfAuthorized()
            }
        } onCancel: {
            Task { @MainActor in self.finish(nil) }
        }
    }

    private func requestIfAuthorized() {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let location = manager.location,
               location.horizontalAccuracy >= 0,
               abs(location.timestamp.timeIntervalSinceNow) < 60 {
                finish(location)
            } else {
                manager.requestLocation()
            }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(nil)
        @unknown default:
            finish(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else { return }
        finish(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        manager.delegate = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: location)
    }
}

enum DrivingTimeLabel {
    static func text(for seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "Directions" }
        let formatter = DateComponentsFormatter()
        // Round up so a short drive never reads as zero minutes.
        let roundedSeconds = max(60, ceil(seconds / 60) * 60)
        formatter.allowedUnits = roundedSeconds < 3600 ? [.minute] : [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: roundedSeconds) ?? "Directions"
    }
}
