import SwiftUI

enum SseEventType { case Error, Message }

struct OllamaMessage: Codable {
    let role: String
    let content: String?
}

struct OllamaRequest: Encodable {
    let appID: String?
    let model: String?
    let messages: [OllamaMessage]
    let stream: Bool
}

struct OllamaResponse: Decodable {
    let model: String
    let message: OllamaMessage
}

@Observable
final class ChattStore {
    static let shared = ChattStore()
    private init() {}
    private(set) var chatts = [Chatt]()
    private let serverUrl = "https://3.143.230.167"

    func llmChat(appID: String, chatt: Chatt, errMsg: Binding<String>) async {
        self.chatts.append(chatt)
        let resChatt = Chatt(
            name: "assistant (\(chatt.name ?? "ollama"))",
            message: "")
        self.chatts.append(resChatt)

        guard let apiUrl = URL(string: "\(serverUrl)/llmchat") else {
            errMsg.wrappedValue = "llmChat: Bad URL"
            return
        }
        let ollamaRequest = OllamaRequest(
            appID: appID,
            model: chatt.name,
            messages: [OllamaMessage(role: "user", content: chatt.message)],
            stream: true
        )
        guard let requestBody = try? JSONEncoder().encode(ollamaRequest) else {
            errMsg.wrappedValue = "llmChat: JSONEncoder error"
            return
        }
        var request = URLRequest(url: apiUrl)
        request.timeoutInterval = 1200
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-streaming", forHTTPHeaderField: "Accept")
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

            // streaming SSE
            var sseEvent = SseEventType.Message
            var line = ""
            for try await char in bytes.characters {
                if char != "\n" && char != "\r\n" {
                    line.append(char)
                    continue
                }
                if line.isEmpty {
                    if sseEvent == .Error {
                        sseEvent = .Message
                        resChatt.message?.append("\n\n**llmChat Error**: \(errMsg.wrappedValue)\n\n")
                    }
                    continue
                }

                // parse SSE line
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let event = parts[1].trimmingCharacters(in: .whitespaces)
                if parts[0].starts(with: "event") {
                    if event == "error" {
                        sseEvent = .Error
                    } else if !event.isEmpty && event != "message" {
                        print("LLMCHAT: Unknown event: '\(parts[1])'")
                    }
                } else if parts[0].starts(with: "data") {
                    let data = Data(event.utf8)
                    do {
                        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
                        if let token = ollamaResponse.message.content {
                            if sseEvent == .Error {
                                errMsg.wrappedValue += token
                            } else {
                                resChatt.message?.append(token)
                            }
                        }
                    } catch {
                        errMsg.wrappedValue += "\(error)\n\(apiUrl)\n\(String(data: data, encoding: .utf8) ?? "decoding error")"
                    }
                }
                line = ""
            }
        } catch {
            errMsg.wrappedValue = "llmChat: failed \(error)"
        }
    }

    func llmPrep(appID: String, chatt: Chatt, errMsg: Binding<String>) async {
        guard let apiUrl = URL(string: "\(serverUrl)/llmprep") else {
            errMsg.wrappedValue = "llmPrep: Bad URL"
            return
        }
        let ollamaRequest = OllamaRequest(
            appID: appID,
            model: chatt.name,
            messages: [OllamaMessage(role: "system", content: chatt.message)],
            stream: false
        )
        guard let requestBody = try? JSONEncoder().encode(ollamaRequest) else {
            errMsg.wrappedValue = "llmPrep: JSONEncoder error"
            return
        }
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errMsg.wrappedValue = "llmPrep: \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
            }
        } catch {
            errMsg.wrappedValue = "llmPrep: failed \(error)"
        }
    }
}
