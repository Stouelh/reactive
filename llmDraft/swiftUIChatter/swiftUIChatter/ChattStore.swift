import Foundation
import SwiftUI

final class ChattStore {
    static let shared = ChattStore()

    
    private let baseURL = URL(string: "http://18.227.21.234:8000")!

    private init() {}

    
    var chatts: [Chatt] = []

    // MARK: - Helpers
    private func setErr(_ msg: String, errMsg: Binding<String>) {
        DispatchQueue.main.async { errMsg.wrappedValue = msg }
    }

    // MARK: - GET /getchatts
    func getChatts(errMsg: Binding<String>) async {
        errMsg.wrappedValue = ""
        let url = baseURL.appendingPathComponent("getchatts")

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse else {
                setErr("getChatts: no HTTP response", errMsg: errMsg)
                return
            }

            guard (200...299).contains(http.statusCode) else {
                setErr("getChatts: HTTP \(http.statusCode)", errMsg: errMsg)
                return
            }

            let decoder = JSONDecoder()
            
            let list = try decoder.decode([Chatt].self, from: data)

            DispatchQueue.main.async {
                self.chatts = list
            }
        } catch {
            setErr("getChatts: \(error.localizedDescription)", errMsg: errMsg)
        }
    }

    
    func getChatts() async {
        await getChatts(errMsg: .constant(""))
    }

    // MARK: - POST /postchatt
    func postChatt(_ chatt: Chatt, errMsg: Binding<String>) async {
        errMsg.wrappedValue = ""
        let url = baseURL.appendingPathComponent("postchatt")

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let encoder = JSONEncoder()
            req.httpBody = try encoder.encode(chatt)

            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                setErr("postChatt: no HTTP response", errMsg: errMsg)
                return
            }
            guard (200...299).contains(http.statusCode) else {
                setErr("postChatt: HTTP \(http.statusCode)", errMsg: errMsg)
                return
            }
        } catch {
            setErr("postChatt: \(error.localizedDescription)", errMsg: errMsg)
        }
    }

    
    func postChatt(_ chatt: Chatt) async {
        await postChatt(chatt, errMsg: .constant(""))
    }

    // MARK: - POST /llmDraft
    private struct LlmChunk: Decodable {
        let response: String?
        let done: Bool?
    }
    
    func llmDraft(_ chatt: Chatt, draft: Binding<String>, errMsg: Binding<String>) async {
        errMsg.wrappedValue = ""
        draft.wrappedValue = ""

        let url = baseURL.appendingPathComponent("llmDraft")

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // backend expects: { model, prompt }
            let body: [String: Any] = [
                "model": chatt.name,
                "prompt": chatt.message ?? ""
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (bytes, resp) = try await URLSession.shared.bytes(for: req)

            guard let http = resp as? HTTPURLResponse else {
                setErr("llmDraft: no HTTP response", errMsg: errMsg)
                return
            }
            guard (200...299).contains(http.statusCode) else {
                setErr("llmDraft: HTTP \(http.statusCode)", errMsg: errMsg)
                return
            }

            let decoder = JSONDecoder()

            for try await line in bytes.lines {
                if line.isEmpty { continue }
                guard let data = line.data(using: .utf8) else { continue }

                if let chunk = try? decoder.decode(LlmChunk.self, from: data),
                   let piece = chunk.response {
                    DispatchQueue.main.async {
                        draft.wrappedValue += piece
                    }
                }
            }
        } catch {
            setErr("llmDraft: \(error.localizedDescription)", errMsg: errMsg)
        }
    }

    func llmDraft(chat: Chatt, draft: Binding<String>, errMsg: Binding<String>) async {
        await llmDraft(chat, draft: draft, errMsg: errMsg)
    }
}
