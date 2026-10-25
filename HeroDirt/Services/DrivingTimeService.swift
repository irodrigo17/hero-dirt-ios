import CoreLocation
import MapKit

protocol DrivingTimeProviding: Sendable {
    @MainActor func travelTime(to destination: CLLocationCoordinate2D) async -> TimeInterval?
}

struct LiveDrivingTimeProvider: DrivingTimeProviding {
    func travelTime(to destination: CLLocationCoordinate2D) async -> TimeInterval? {
        guard let location = await DrivingLocationRequest.location(), !Task.isCancelled else { return nil }
        return await travelTime(from: location, to: destination)
    }

    nonisolated func travelTime(from location: CLLocation, to destination: CLLocationCoordinate2D) async -> TimeInterval? {
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

/// Read one fresh fix on the cooperative executor. CLLocationManager's
/// synchronous authorization/location getters can wait on locationd; never
/// perform those reads on the UI actor during the detail transition.
/// Ending iteration (or cancelling it after 15 seconds) stops the updates.
enum DrivingLocationRequest {
    static func location(
        timeout: Duration = .seconds(15),
        receive: @escaping @Sendable () async -> CLLocation? = { await firstLocation() }
    ) async -> CLLocation? {
        guard !Task.isCancelled else { return nil }
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { await receive() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let location = await group.next() ?? nil
            group.cancelAll()
            return Task.isCancelled ? nil : location
        }
    }

    private static func firstLocation() async -> CLLocation? {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard !Task.isCancelled else { return nil }
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return nil
                }
                if let location = update.location, location.horizontalAccuracy >= 0,
                   abs(location.timestamp.timeIntervalSinceNow) < 60 {
                    return location
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}

enum DrivingTimeLabel {
    static func text(for seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return String(localized: "Directions") }
        let formatter = DateComponentsFormatter()
        // Round up so a short drive never reads as zero minutes.
        let roundedSeconds = max(60, ceil(seconds / 60) * 60)
        formatter.allowedUnits = roundedSeconds < 3600 ? [.minute] : [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: roundedSeconds) ?? String(localized: "Directions")
    }
}

/// Saved rows can open driving directions immediately, without fetching place
/// metadata or loading the detail screen first.
enum DrivingDirections {
    @MainActor
    static func open(to place: Place) {
        let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        item.name = place.name
        Telemetry.signal(.directionsOpened)
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
