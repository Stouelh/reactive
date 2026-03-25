import SwiftUI

@Observable
final class ChattViewModel {
    let onTrailingEnd = "gemma3:270m"
    let instruction = "Type a message…"
    var message = "howdy?"
    var errMsg = ""
    var showError = false
    let appID = Bundle.main.bundleIdentifier
    let sysmsg = "Start every assistant reply with GO BLUE!!!"
}

@main
struct swiftUIChatterApp: App {
    let viewModel = ChattViewModel()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .onAppear {
                        let scenes = UIApplication.shared.connectedScenes
                        let windowScene = scenes.first as? UIWindowScene
                        if let wnd = windowScene?.windows.first {
                            let lagFreeField = UITextField()
                            wnd.addSubview(lagFreeField)
                            lagFreeField.becomeFirstResponder()
                            lagFreeField.resignFirstResponder()
                            lagFreeField.removeFromSuperview()
                        }
                    }
            }
            .environment(viewModel)
        }
    }
    
    init() {
        Task { [self] in
            if let appID = viewModel.appID, !viewModel.sysmsg.isEmpty {
                await ChattStore.shared.llmPrep(
                    appID: appID,
                    chatt: Chatt(name: viewModel.onTrailingEnd, message: viewModel.sysmsg),
                    errMsg: Bindable(viewModel).errMsg)
                viewModel.showError = !viewModel.errMsg.isEmpty
            }
        }
    }
}
