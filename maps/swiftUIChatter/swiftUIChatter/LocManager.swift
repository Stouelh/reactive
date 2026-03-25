import MapKit
import Observation

struct Location {
    var lat: CLLocationDegrees
    var lon: CLLocationDegrees
    var speed: CLLocationSpeed
}

@Observable
final class LocManagerViewModel {
    static let shared = LocManagerViewModel()
    private init() {}
    
    private(set) var location = Location(lat: 0.0, lon: 0.0, speed: 0.0)
    
    @ObservationIgnored
    var speed: String {
        switch location.speed {
        case 0.5..<5: "walking"
        case 5..<7: "running"
        case 7..<13: "cycling"
        case 13..<90: "driving"
        case 90..<139: "in train"
        case 139..<225: "flying"
        default: "resting"
        }
    }
    
    func setLocation(lat: CLLocationDegrees, lon: CLLocationDegrees, speed: CLLocationSpeed) {
        location.lat = lat
        location.lon = lon
        location.speed = speed
    }
    
    @ObservationIgnored
    private(set) var heading: CLLocationDirection? = nil
    private let compass = ["North", "NE", "East", "SE", "South", "SW", "West", "NW", "North"]
    
    @ObservationIgnored
    var compassHeading: String {
        return if let heading {
            compass[Int(round(heading.truncatingRemainder(dividingBy: 360) / 45))]
        } else {
            "unknown"
        }
    }
    
    func setHeading(_ newHeading: CLLocationDirection?) {
        heading = newHeading
    }
}

final class LocManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocManager()
    private let locManager = CLLocationManager()
    
    override private init() {
        super.init()
        locManager.desiredAccuracy = kCLLocationAccuracyBest
        locManager.delegate = self
    }
    
    func startUpdates() {
        if locManager.authorizationStatus == .notDetermined {
            locManager.requestWhenInUseAuthorization()
        }
        Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let loc = update.location {
                        LocManagerViewModel.shared.setLocation(
                            lat: loc.coordinate.latitude,
                            lon: loc.coordinate.longitude,
                            speed: loc.speed)
                    }
                }
            } catch {
                print(error.localizedDescription)
            }
        }
        Task {
            for await newHeading in headings {
                LocManagerViewModel.shared.setHeading(newHeading)
            }
        }
    }
    
    var feeder: ((CLLocationDirection) -> Void)?
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        feeder?(newHeading.magneticHeading)
    }
    
    var headings: AsyncStream<CLLocationDirection> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont in
            feeder = { cont.yield($0) }
            cont.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.locManager.stopUpdatingHeading()
                    self.feeder = nil
                }
            }
            locManager.startUpdatingHeading()
        }
    }
}
