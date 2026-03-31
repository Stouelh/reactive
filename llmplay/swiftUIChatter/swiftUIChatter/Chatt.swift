import Foundation

struct Chatt: Identifiable {
    var name: String?
    var message: String?
    var id: UUID?
    var timestamp: String?
    
    init(name: String? = nil, message: String? = nil, id: UUID? = nil, timestamp: String? = nil) {
        self.name = name
        self.message = message
        self.id = id ?? UUID()
        self.timestamp = timestamp ?? Date().ISO8601Format()
    }
    
    static func ==(lhs: Chatt, rhs: Chatt) -> Bool {
        lhs.id == rhs.id
    }
}
