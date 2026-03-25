import SwiftUI
import Synchronization

@Observable
final class ChattStore {
    static let shared = ChattStore()
    private init() {}
    private(set) var chatts = [Chatt]()
    private let serverUrl = "https://3.143.230.167"
    private let nFields = Mirror(reflecting: Chatt()).children.count
    private let mutex = Mutex(false)
    private var isRetrieving = false

    func postChatt(_ chatt: Chatt, errMsg: Binding<String>) async {
        guard let apiUrl = URL(string: "\(serverUrl)/postmaps") else {
            errMsg.wrappedValue = "postChatt: Bad URL"
            return
        }
        var geoObj: Data?
        if let geodata = chatt.geodata {
            geoObj = try? JSONSerialization.data(withJSONObject: [geodata.lat, geodata.lon, geodata.facing, geodata.speed])
        }
        let chattObj = ["name": chatt.name,
                        "message": chatt.message,
                        "geodata": (geoObj == nil) ? nil : String(data: geoObj!, encoding: .utf8)]
        guard let requestBody = try? JSONSerialization.data(withJSONObject: chattObj) else {
            errMsg.wrappedValue = "postChatt: JSONSerialization error"
            return
        }
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errMsg.wrappedValue = "postChatt: \(http.statusCode)\n\(apiUrl)\n\(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
            }
        } catch {
            errMsg.wrappedValue = "postChatt: POSTing failed \(error)"
        }
    }

    func getChatts(errMsg: Binding<String>) async {
        let inProgress = mutex.withLock { _ in
            guard !self.isRetrieving else { return true }
            self.isRetrieving = true
            return false
        }
        if inProgress { return }
        defer {
            mutex.withLock { _ in
                self.isRetrieving = false
            }
        }
        guard let apiUrl = URL(string: "\(serverUrl)/getmaps") else {
            errMsg.wrappedValue = "getChatts: Bad URL"
            return
        }
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "GET"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errMsg.wrappedValue = "getChatts: \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
                return
            }
            guard let chattsReceived = try? JSONSerialization.jsonObject(with: data) as? [[String?]] else {
                errMsg.wrappedValue = "getChatts: failed JSON deserialization"
                return
            }
            chatts = [Chatt]()
            for chattEntry in chattsReceived {
                if chattEntry.count == self.nFields {
                    let geoArr = chattEntry[4]?.data(using: .utf8).flatMap {
                        try? JSONSerialization.jsonObject(with: $0) as? [Any]
                    }
                    chatts.append(Chatt(name: chattEntry[0],
                                       message: chattEntry[1],
                                       id: UUID(uuidString: chattEntry[2] ?? ""),
                                       timestamp: chattEntry[3],
                                       geodata: geoArr.map {
                                           GeoData(lat: $0[0] as! Double,
                                                   lon: $0[1] as! Double,
                                                   facing: $0[2] as! String,
                                                   speed: $0[3] as! String)
                                       }))
                } else {
                    errMsg.wrappedValue = "getChatts: Received unexpected number of fields: \(chattEntry.count) instead of \(self.nFields)"
                }
            }
        } catch {
            errMsg.wrappedValue = "getChatts: Failed GET request \(error)"
        }
    }
}
