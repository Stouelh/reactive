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
        guard let apiUrl = URL(string: "\(serverUrl)/postchatt") else {
            errMsg.wrappedValue = "postChatt: Bad URL"
            return
        }
        let chattObj = ["name": chatt.name, "message": chatt.message]
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
        guard let apiUrl = URL(string: "\(serverUrl)/getchatts") else {
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
                    chatts.append(Chatt(name: chattEntry[0],
                                       message: chattEntry[1],
                                       id: UUID(uuidString: chattEntry[2] ?? ""),
                                       timestamp: chattEntry[3]))
                } else {
                    errMsg.wrappedValue = "getChatts: Received unexpected number of fields: \(chattEntry.count) instead of \(self.nFields)"
                }
            }
        } catch {
            errMsg.wrappedValue = "getChatts: Failed GET request \(error)"
        }
    }
}
