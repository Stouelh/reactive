@preconcurrency
import MapKit

struct GeoData: Hashable {
    var lat: Double = 0.0
    var lon: Double = 0.0
    var facing: String = "unknown"
    var speed: String = "unknown"
    
    var place: String {
        get async {
            if #available(iOS 26.0, *) {
                if let revGeocoder = MKReverseGeocodingRequest(
                    location: CLLocation(latitude: lat, longitude: lon)),
                   let geolocs = try? await revGeocoder.mapItems,
                   let address = geolocs.first?.address {
                    return address.shortAddress ?? (address.fullAddress.isEmpty ? "place unknown" : address.fullAddress)
                }
            } else {
                if let geolocs = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) {
                    return geolocs[0].locality ?? geolocs[0].administrativeArea ?? geolocs[0].country ?? "place unknown"
                }
            }
            return "place unknown"
        }
    }
    
    var postedFrom: AttributedString {
        get async {
            let place = await self.place
            var posted = try! AttributedString(markdown: "Posted from **\(place)** while facing **\(facing)** moving at **\(speed)** speed")
            ["\(place)", "\(facing)", "\(speed)"].forEach {
                if !$0.isEmpty {
                    if let range = posted.range(of: $0) {
                        posted[range].foregroundColor = .blue
                    }
                }
            }
            return posted
        }
    }
}
