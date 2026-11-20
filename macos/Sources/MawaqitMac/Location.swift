import CoreLocation
import Foundation

/// Requests a single location only after the user presses the location button.
@MainActor
final class LocationLookup: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocationCoordinate2D, Error>) -> Void)?
    private var timeout: Task<Void, Never>?

    /// Called with a reason when location can't be used (system-wide off, or Mawaqit denied), else nil.
    var onAvailabilityChange: ((String?) -> Void)? {
        didSet { refreshAvailability() }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refreshAvailability() {
        let status = manager.authorizationStatus
        // locationServicesEnabled() can block, so query it off the main thread.
        Task.detached {
            let enabled = CLLocationManager.locationServicesEnabled()
            await MainActor.run { [weak self] in
                let reason: String? = if !enabled {
                    "Location Services is off. Turn it on in System Settings → Privacy & Security, or enter a city."
                } else if status == .denied || status == .restricted {
                    "Mawaqit can’t use your location. Allow it in System Settings → Privacy & Security → Location Services, or enter a city."
                } else { nil }
                self?.onAvailabilityChange?(reason)
            }
        }
    }

    func request(completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { return }
            self?.finish(.failure(MawaqitError.message("Could not get your location. Try again or enter a city.")))
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: denied()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAvailability()
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: denied()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 120 else { return }
        finish(.success(location.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { denied() }
        else { finish(.failure(MawaqitError.message("Could not get your location. Try again or enter a city."))) }
    }

    private func denied() {
        finish(.failure(MawaqitError.message("Allow Mawaqit in System Settings → Privacy & Security → Location Services, or enter a city.")))
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        let callback = completion
        completion = nil
        callback?(result)
    }
}
