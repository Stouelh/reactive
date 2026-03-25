import SwiftUI

@Observable
final class ChattViewModel {
    let onTrailingEnd = "me"

    let instruction = "Type a message…"
    var message: String = ""

    // LLM draft stream goes here
    var draft: String = ""

    // prevents multiple concurrent LLM requests 
    var llmInProgress: Bool = false

    var errMsg: String = ""
    var showError: Bool = false

    // optional: track selection
    var selectedChattId: UUID? = nil
}

@main
struct swiftUIChatterApp: App {
    let vm = ChattViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .environment(vm)
        }
    }
}
