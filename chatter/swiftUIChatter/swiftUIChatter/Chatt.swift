import Foundation

struct Chatt: Identifiable {
    var name: String?
    var message: String?
    var id: UUID?
    var timestamp: String?
    
    static func ==(lhs: Chatt, rhs: Chatt) -> Bool {
        lhs.id == rhs.id
    }
}
