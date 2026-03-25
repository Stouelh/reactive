import Foundation

struct Chatt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var message: String?
    var timestamp: String

    init(id: UUID = UUID(), name: String, message: String? = nil, timestamp: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id
        self.name = name
        self.message = message
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case message
        case timestamp = "time"   // ✅ map server "time" -> app "timestamp"
    }
}
