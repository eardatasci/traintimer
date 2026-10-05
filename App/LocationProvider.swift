import CoreLocation
import TrainTimerCore

/// Wraps CLLocationManager. Set the `fixedLocation` default ("lat,lon") to skip
/// Location Services entirely, e.g. `defaults write local.traintimer.TrainTimer fixedLocation "40.7359,-73.9906"`.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        case locating
        case denied
        case located(Coordinate)
    }

    var onChange: ((Status) -> Void)?
    private(set) var status: Status = .locating {
        didSet { if status != oldValue { onChange?(status) } }
    }

    private let manager = CLLocationManager()

    func start() {
        if let fixed = UserDefaults.standard.string(forKey: "fixedLocation").flatMap(Coordinate.init(string:)) {
            status = .located(fixed)
            return
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        handleAuthorization()
    }

    private func handleAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    // CLLocationManager calls back on the thread it was created on: the main thread.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { handleAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let location = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        MainActor.assumeIsolated { status = .located(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // kCLErrorLocationUnknown is transient; CoreLocation keeps trying.
        guard (error as? CLError)?.code == .denied else { return }
        MainActor.assumeIsolated { status = .denied }
    }
}
