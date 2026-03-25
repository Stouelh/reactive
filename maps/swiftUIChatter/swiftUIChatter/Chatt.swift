import Foundation

struct Chatt: Identifiable, Hashable {
    var name: String?
    var message: String?
    var id: UUID?
    var timestamp: String?
    var geodata: GeoData?
    
    static func ==(lhs: Chatt, rhs: Chatt) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
