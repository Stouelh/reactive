import SwiftUI

@Observable
final class ChattViewModel {
    var onTrailingEnd = ""
    let modelName = "qwen3:0.6b"
    let instruction = "Type your message..."
    var message = ""
    var errMsg = ""
    var showError = false
    let appID = Bundle.main.bundleIdentifier
    let sysmsg = ""
    var showOk = false
    var getSignedin: Bool = false
    @ObservationIgnored var signinCompletion: (() async -> Void)?
}

@main
struct swiftUIChatterApp: App {
    let viewModel = ChattViewModel()

    init() {
        ChattViewModelHolder.shared.vm = viewModel
        LocManager.shared.startUpdates()
        Task(priority: .background) { [self] in
            await ChatterID.shared.open(errMsg: Bindable(viewModel).errMsg, showOk: Bindable(viewModel).showOk)
            if !ChatterID.shared.creator.isEmpty {
                viewModel.onTrailingEnd = ChatterID.shared.creator  // restore name from keychain
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
