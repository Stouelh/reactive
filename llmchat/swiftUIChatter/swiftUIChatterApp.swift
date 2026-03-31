import SwiftUI
import MapKit

@Observable
final class ChattViewModel {
    let onTrailingEnd = "gemma3:12b"
    let instruction = "Type your guess..."
    var message = ""
    var errMsg = ""
    var showError = false
    let appID = Bundle.main.bundleIdentifier
    var hints = ""
    let sysmsg = "Think of a city. Do not tell the user the name of the city. Ask the user if they are ready to start. If so, give the user 2 to 3 hints at a time and let the user guess. If the user guessed wrong, give them more hints about the city they guessed wrong. When they guessed right, say the following **in the provided format**, along with the lat/lon of the city, and then ask the user if they want to play again. If yes, give them the 2 to 3 hints for the next city:WINNER!!!:lat:lon:"
}

@main
struct swiftUIChatterApp: App {
    let viewModel = ChattViewModel()
    
    init() {
        LocManager.shared.startUpdates()
        Task { [self] in
            if let appID = viewModel.appID {
                await ChattStore.shared.llmPrep(
                    appID: appID,
                    chatt: Chatt(name: viewModel.onTrailingEnd, message: viewModel.sysmsg),
                    errMsg: Bindable(viewModel).errMsg)
                viewModel.showError = !viewModel.errMsg.isEmpty
                await ChattStore.shared.llmPlay(
                  appID: appID,
                  chatt: Chatt(name: viewModel.onTrailingEnd, message: "Yes"),
                  hints: Bindable(viewModel).hints,
                  winner: nil,
                  errMsg: Bindable(viewModel).errMsg)
            }
        }
    }
    
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
}
