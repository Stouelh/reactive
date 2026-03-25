import SwiftUI

struct OllamaReply: Decodable {
    let model: String
    let response: String
}

@Observable
final class ChattStore {
    static let shared = ChattStore()
    private init() {}
    private(set) var chatts = [Chatt]()
    private let serverUrl = "https://3.143.230.167"
    
    // networking methods
    func llmPrompt(_ chatt: Chatt, errMsg: Binding<String>) async {
        self.chatts.append(chatt)
        
        let resChatt = Chatt(
            name: "assistant (\(chatt.name ?? "ollama"))",
            message: "")
        self.chatts.append(resChatt)
        
        guard let apiUrl = URL(string: "\(serverUrl)/llmprompt") else {
            errMsg.wrappedValue = "llmPrompt: Bad URL"
            return
        }
        let ollamaRequest: [String: Any] = [
            "model": chatt.name as Any,
            "prompt": chatt.message as Any,
            "stream": true
        ]
        
        guard let requestBody = try? JSONSerialization.data(withJSONObject: ollamaRequest) else {
            errMsg.wrappedValue = "llmPrompt: JSONSerialization error"
            return
        }
        
        var request = URLRequest(url: apiUrl)
        request.timeoutInterval = 1200
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/*", forHTTPHeaderField: "Accept")
        request.httpBody = requestBody
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                var msg = ""
                for try await line in bytes.lines {
                    guard let data = line.data(using: .utf8) else { continue }
                    msg += String(data: data, encoding: .utf8) ?? ""
                }
                errMsg.wrappedValue = "\(http.statusCode)\n\(apiUrl)\n\(msg.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : msg)"
                return
            }
            
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8) else { continue }
                do {
                    let ollamaResponse = try JSONDecoder().decode(OllamaReply.self, from: data)
                    resChatt.message?.append(ollamaResponse.response)
                } catch {
                    errMsg.wrappedValue += "\(error)\n\(apiUrl)\n\(String(data: data, encoding: .utf8) ?? "decoding error")"
                    resChatt.message?.append("\nllmPrompt Error: \(errMsg.wrappedValue)\n\n")
                }
            }
        } catch {
            errMsg.wrappedValue = "llmPrompt: failed \(error)"
        }
    }
}
