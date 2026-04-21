import SwiftUI

@Observable
final class ChattViewModel {
    var onTrailingEnd = "gemma3:12b"
    let instruction = "Type your message..."
    var message = ""
    var errMsg = ""
    var showError = false
    let appID = Bundle.main.bundleIdentifier
    var showOk = false
    var getSignedin: Bool = false
    @ObservationIgnored var signinCompletion: (() async -> Void)?
}

@main
struct swiftUIChatterApp: App {
    let viewModel = ChattViewModel()

    init() {
        Task(priority: .background) { [self] in
            await ChatterID.shared.open(errMsg: Bindable(viewModel).errMsg, showOk: Bindable(viewModel).showOk)
            if !ChatterID.shared.creator.isEmpty {
                viewModel.onTrailingEnd = ChatterID.shared.creator
            }
        }
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
