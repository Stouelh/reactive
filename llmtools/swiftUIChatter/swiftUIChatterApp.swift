import SwiftUI

@Observable
final class ChattViewModel {
    let onTrailingEnd = "qwen3:0.6b"
    let instruction = "Type your message..."
    var message = "What is the weather at my location?"
    var errMsg = ""
    var showError = false
    let appID = Bundle.main.bundleIdentifier
    let sysmsg = ""
}

@main
struct swiftUIChatterApp: App {
    let viewModel = ChattViewModel()

    init() {
        LocManager.shared.startUpdates()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .environment(viewModel)
        }
    }
}
