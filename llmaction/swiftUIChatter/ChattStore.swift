import SwiftUI

enum SseEventType { case Error, Message, ToolCalls }

struct OllamaMessage: Codable {
    let role: String
    let content: String?
    let thinking: String?
    let toolCalls: [OllamaToolCall]?

    enum CodingKeys: String, CodingKey {
        case role = "role"
        case content = "content"
        case thinking = "thinking"
        case toolCalls = "tool_calls"
    }
}

struct OllamaRequest: Encodable {
    let appID: String?
    let model: String?
    var messages: [OllamaMessage]
    let stream: Bool
    var tools: [OllamaToolSchema]?
}

struct OllamaResponse: Decodable {
    let model: String
    let message: OllamaMessage
}

@Observable
final class ChattStore {
    static let shared = ChattStore()
    private init() {}
    private let serverUrl = "https://3.143.230.167"
    var chatts = [Chatt]()

    func llmTools(appID: String, chatt: Chatt, errMsg: Binding<String>) async {
        guard let apiUrl = URL(string: "\(serverUrl)/llmtools") else {
            errMsg.wrappedValue = "llmTools: Bad URL"
            return
        }

        var ollamaRequest = OllamaRequest(
            appID: appID,
            model: chatt.name,
            messages: [OllamaMessage(role: "user", content: chatt.message, thinking: nil, toolCalls: nil)],
            stream: true,
            tools: TOOLBOX.isEmpty ? nil : []
        )

        for (_, tool) in TOOLBOX {
            ollamaRequest.tools?.append(tool.schema)
        }

        var request = URLRequest(url: apiUrl)
        request.timeoutInterval = 1200
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-streaming", forHTTPHeaderField: "Accept")

        var resChatt = Chatt(name: chatt.name, message: "")
        chatts.append(resChatt)

        var sendNewPrompt = true
        while sendNewPrompt {
            sendNewPrompt = false

            guard let requestBody = try? JSONEncoder().encode(ollamaRequest) else {
                errMsg.wrappedValue = "llmTools: JSONEncoder error"
                return
            }
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

                var sseEvent = SseEventType.Message
                var line = ""
                let decoder = JSONDecoder()
                for try await char in bytes.characters {
                    if char != "\n" && char != "\r\n" {
                        line.append(char)
                        continue
                    }
                    if line.isEmpty {
                        sseEvent = .Message
                        continue
                    }

                    let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count >= 2 else { line = ""; continue }

                    if parts[0].starts(with: "event") {
                        let event = parts[1].trimmingCharacters(in: .whitespaces)
                        if event == "error" {
                            sseEvent = .Error
                        } else if event == "tool_calls" {
                            sseEvent = .ToolCalls
                        } else if !event.isEmpty && event != "message" {
                            print("llmTools: Unknown event: '\(parts[1])'")
                        }
                    } else if parts[0].starts(with: "data") {
                        if sseEvent == .Error {
                            errMsg.wrappedValue += String(describing: parts[1].trimmingCharacters(in: .whitespaces).utf8)
                            line = ""
                            continue
                        }

                        let data = Data(parts[1].trimmingCharacters(in: .whitespaces).utf8)

                        do {
                            let ollamaResponse = try decoder.decode(OllamaResponse.self, from: data)

                            if let token = ollamaResponse.message.content, !token.isEmpty {
                                resChatt.message?.append(token)
                                if let idx = chatts.firstIndex(where: { $0.id == resChatt.id }) {
                                    chatts[idx] = resChatt
                                }
                            } else if let token = ollamaResponse.message.thinking, !token.isEmpty {
                                resChatt.message?.append(token)
                                if let idx = chatts.firstIndex(where: { $0.id == resChatt.id }) {
                                    chatts[idx] = resChatt
                                }
                            }

                            if sseEvent == .ToolCalls, let toolCalls = ollamaResponse.message.toolCalls {
                                for toolCall in toolCalls {
                                    let toolResult = await toolInvoke(function: toolCall.function)
                                    if toolResult != nil {
                                        ollamaRequest.messages = [OllamaMessage(role: "tool", content: toolResult, thinking: nil, toolCalls: nil)]
                                        ollamaRequest.tools = nil
                                        sendNewPrompt = true
                                    } else {
                                        errMsg.wrappedValue += "llmTools ERROR: tool '\(toolCall.function.name)' called"
                                        resChatt.message?.append("\n\n**llmTools Error**: tool '\(toolCall.function.name)' called\n\n")
                                        if let idx = chatts.firstIndex(where: { $0.id == resChatt.id }) {
                                            chatts[idx] = resChatt
                                        }
                                    }
                                }
                            }
                        } catch {
                            errMsg.wrappedValue += "\(error)\n\(apiUrl)\n\(String(data: data, encoding: .utf8) ?? "decoding error")"
                        }
                    }
                    line = ""
                }
            } catch {
                errMsg.wrappedValue = "llmTools: failed \(error)"
            }
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
            messages: [OllamaMessage(role: "system", content: chatt.message, thinking: nil, toolCalls: nil)],
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
