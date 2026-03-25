import Foundation

@Observable
final class Chatt: Identifiable {
    @ObservationIgnored var name: String?
    var message: String?
    @ObservationIgnored var id: UUID?
    @ObservationIgnored var timestamp: String?
    
    init() {}
    init(name: String?, message: String?, id: UUID? = nil, timestamp: String? = nil) {
        self.name = name
        self.message = message
        self.id = id ?? UUID()
        self.timestamp = timestamp ?? Date().ISO8601Format()
    }
    
    // so that we don't need to compare every property for equality
    static func ==(lhs: Chatt, rhs: Chatt) -> Bool {
        lhs.id == rhs.id
    }
}
