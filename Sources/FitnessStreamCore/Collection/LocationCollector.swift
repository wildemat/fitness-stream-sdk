import CoreLocation
import Foundation

/// Delegate protocol for location updates within the SDK.
public protocol LocationCollectorDelegate: AnyObject {
    func locationCollector(_ collector: LocationCollector, didUpdate location: CLLocation)
}

/// CoreLocation wrapper for collecting GPS data during a workout.
public final class LocationCollector: NSObject, CLLocationManagerDelegate {

    private let clManager = CLLocationManager()
    public weak var delegate: LocationCollectorDelegate?

    /// Latest location values, updated on every CLLocation callback.
    public private(set) var latitude: Double?
    public private(set) var longitude: Double?
    public private(set) var elevation: Double?

    public override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.activityType = .fitness
        clManager.allowsBackgroundLocationUpdates = true
        clManager.showsBackgroundLocationIndicator = true
    }

    public func requestAuthorization() {
        clManager.requestWhenInUseAuthorization()
    }

    public func start() {
        clManager.startUpdatingLocation()
    }

    public func stop() {
        clManager.stopUpdatingLocation()
        latitude = nil
        longitude = nil
        elevation = nil
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        elevation = loc.altitude
        delegate?.locationCollector(self, didUpdate: loc)
    }

    /// Collect current location values as metric dictionary entries.
    public func currentValues() -> [String: MetricValue] {
        var values: [String: MetricValue] = [:]
        if let lat = latitude { values["latitude"] = .double(lat) }
        if let lon = longitude { values["longitude"] = .double(lon) }
        if let elev = elevation { values["elevation_meters"] = .double(elev) }
        return values
    }
}
