import SwiftUI

@Observable
final class ChattStore {
    static let shared = ChattStore()
    private init() {}
    private let serverUrl = "https://3.143.230.167"

    var chatts = [Chatt]()

    func getChatts(errMsg: Binding<String>) async {
        guard let apiUrl = URL(string: "\(serverUrl)/getchatts") else {
            errMsg.wrappedValue = "getChatts: Bad URL"
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: apiUrl)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errMsg.wrappedValue = "getChatts: \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
                return
            }
            let rawChatts = try JSONDecoder().decode([[String?]].self, from: data)
            chatts = rawChatts.compactMap { arr in
                guard arr.count >= 3, let name = arr[0], let message = arr[1] else { return nil }
                return Chatt(name: name, message: message)
            }
        } catch {
            errMsg.wrappedValue = "getChatts: \(error)"
        }
    }

    func postChatt(_ chatt: Chatt, errMsg: Binding<String>) async {
        guard let apiUrl = URL(string: "\(serverUrl)/postauth") else {
            errMsg.wrappedValue = "postChatt: Bad URL"
            return
        }
        let chattObj: [String: Any?] = [
            "chatterID": ChatterID.shared.id,
            "message": chatt.message
        ]
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
                errMsg.wrappedValue = "postChatt: \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
            }
        } catch {
            errMsg.wrappedValue = "postChatt: \(error)"
        }
    }

    func addUser(_ idToken: String?, errMsg: Binding<String>) async -> String? {
        guard let idToken else {
            return nil
        }
        guard let apiUrl = URL(string: "\(serverUrl)/adduser") else {
            errMsg.wrappedValue = "addUser: Bad URL"
            return nil
        }
        let authObj = ["clientID": "892681361227-slq75m5enai2gsva2c0i00ta4mrvtglr.apps.googleusercontent.com",
                       "idToken": idToken]
        guard let requestBody = try? JSONSerialization.data(withJSONObject: authObj) else {
            errMsg.wrappedValue = "addUser: JSONSerialization error"
            return nil
        }
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errMsg.wrappedValue = "addUser: \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))\n\(String(data: data, encoding: .utf8) ?? "")"
                return nil
            }
            // obtain username and chatterID from back end
            guard let chatterObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errMsg.wrappedValue = "addUser: JSON deserialization"
                return nil
            }
            if let creator = chatterObj["username"] as? String {
                if creator.count > 32 {
                    errMsg.wrappedValue = "addUser: creator name (\(creator) longer than 32 characters"
                    return nil
                }
                ChatterID.shared.creator = creator
            }
            ChatterID.shared.id = chatterObj["chatterID"] as? String
            ChatterID.shared.expiration = Date() + (chatterObj["lifetime"] as! TimeInterval)
            return ChatterID.shared.id
        } catch {
            errMsg.wrappedValue = "addUser: POSTing failed \(error)"
            return nil
        }
    }
}
