import Foundation

struct OllamaToolSchema: Codable {
    let type: String
    let function: OllamaToolFunction
}

struct OllamaToolFunction: Codable {
    let name: String
    let description: String
    let parameters: OllamaFunctionParams?
}

struct OllamaFunctionParams: Codable {
    let type: String
    let properties: [String: OllamaParamProp]?
    let required: [String]?
}

struct OllamaParamProp: Codable {
    let type: String
    let description: String
    let enum_: [String]?

    enum CodingKeys: String, CodingKey {
        case type = "type"
        case description = "description"
        case enum_ = "enum"
    }
}

func jsonToSchema(_ tool: String) -> OllamaToolSchema {
    guard let url = Bundle.main.url(forResource: tool, withExtension: "json"),
          let data = try? Data(contentsOf: url) else {
        fatalError("Failed to find \(tool).json in bundle")
    }
    do {
        return try JSONDecoder().decode(OllamaToolSchema.self, from: data)
    } catch {
        fatalError("Failed to decode \(tool).json: \(error)")
    }
}

func getLocation(_ argv: [String]) async -> String? {
    "latitude: \(LocManagerViewModel.shared.location.lat), longitude: \(LocManagerViewModel.shared.location.lon)"
}

func getAuth(_ argv: [String]) async -> String? {
    // Signal the UI to trigger Google Sign-In + biometric auth
    // Returns the chatterID if successful, nil otherwise
    return await withUnsafeContinuation { cont in
        Task { @MainActor in
            guard let vm = ChattViewModelHolder.shared.vm else {
                cont.resume(returning: nil)
                return
            }
            vm.signinCompletion = {
                cont.resume(returning: ChatterID.shared.id)
            }
            vm.getSignedin = true
        }
    }
}

typealias ToolFunction = ([String]) async -> String?

struct Tool {
    let schema: OllamaToolSchema
    let function: ToolFunction
}

let TOOLBOX: [String: Tool] = [
    "get_location": Tool(schema: jsonToSchema("get_location"), function: getLocation),
    "get_auth": Tool(schema: jsonToSchema("get_auth"), function: getAuth),
]

struct OllamaToolCall: Codable {
    let function: OllamaFunctionCall
}

struct OllamaFunctionCall: Codable {
    let name: String
    let arguments: [String: String]
}

func toolInvoke(function: OllamaFunctionCall) async -> String? {
    if let tool = TOOLBOX[function.name] {
        var argv = [String]()
        for label in tool.schema.function.parameters?.required ?? [] {
            if let arg = function.arguments[label] {
                argv.append(arg)
            }
        }
        return await tool.function(argv)
    }
    return nil
}
