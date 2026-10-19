import CoreLocation
import Foundation

@MainActor
final class LocationClient: NSObject, CLLocationManagerDelegate {
    var onLocation: ((Double, Double) -> Void)?
    var onAuthorizationChange: ((Bool) -> Void)?

    private let manager = CLLocationManager()
    private var waitingForFix = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isDenied: Bool {
        switch manager.authorizationStatus {
        case .denied, .restricted: true
        default: false
        }
    }

    func requestCurrentLocation() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            waitingForFix = true
            manager.requestWhenInUseAuthorization()
        } else if Self.isAuthorized(status) {
            waitingForFix = true
            manager.requestLocation()
        } else {
            onAuthorizationChange?(true)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor in
            self.waitingForFix = false
            self.onLocation?(latitude, longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.waitingForFix = false
        }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        let denied = status == .denied || status == .restricted
        onAuthorizationChange?(denied)
        if waitingForFix, Self.isAuthorized(status) {
            manager.requestLocation()
        }
        if denied {
            waitingForFix = false
        }
    }

    /// When-in-use on iOS. On macOS the same request reports as always-authorized.
    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways:
            return true
        #if os(iOS)
        case .authorizedWhenInUse:
            return true
        #endif
        default:
            return false
        }
    }
}
