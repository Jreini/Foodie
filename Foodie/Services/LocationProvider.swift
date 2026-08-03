import Foundation
import CoreLocation

// One-shot location lookups for restaurant search.
//
// Deliberately not a continuous tracker: Foodie only needs "roughly where am I"
// to seed a MapKit search region, so this asks once and stops. Hundred-metre
// accuracy is plenty for that and costs far less battery than full precision.
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    // Resumed exactly once each, then cleared. Holding them as optionals is
    // what makes the "already resumed" check cheap.
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    // Returns nil rather than throwing when location is unavailable — callers
    // fall back to a default region, and "user said no" isn't an error worth
    // surfacing as one.
    func currentLocation() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await requestAuthorization()
        }

        guard !isDenied else { return nil }

        // A recent fix avoids waking the GPS at all.
        if let cached = manager.location {
            return cached
        }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func requestAuthorization() async {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Fires once for the initial status too, so ignore anything that isn't
        // the user actually answering the prompt.
        guard manager.authorizationStatus != .notDetermined else { return }

        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationContinuation?.resume(returning: locations.last)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }
}
