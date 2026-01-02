import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationResult?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() async -> LocationResult? {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            return nil
        }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<LocationResult?, Never>) in
            continuation = cont
            manager.requestLocation()
        }
    }

    private func reverseGeocode(location: CLLocation) async -> CLPlacemark? {
        let geocoder = CLGeocoder()
        return try? await geocoder.reverseGeocodeLocation(location).first
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let cont = continuation else { return }
            continuation = nil
            guard let location = locations.first else {
                cont.resume(returning: nil)
                return
            }
            let placemark = await reverseGeocode(location: location)
            cont.resume(returning: LocationResult(location: location, placemark: placemark))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}

struct LocationResult {
    let location: CLLocation
    let placemark: CLPlacemark?

    var displayName: String? {
        if let name = placemark?.name { return name }
        if let locality = placemark?.locality { return locality }
        return placemark?.country
    }
}
